using System.ComponentModel.DataAnnotations;
using System.Security.Claims;
using System.Text.Json;
using Bma.Data;
using Bma.Domain;
using Bma.Modules;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.EntityFrameworkCore;

namespace Bma.Pages.Admin.Announcements;

[Authorize(Policy = "Admin")]
public sealed class IndexModel(BmaDbContext db, AuditWriter audit) : PageModel
{
    [BindProperty] public AnnouncementInput Input { get; set; } = new();
    public List<Announcement> Items { get; private set; } = [];

    public async Task OnGetAsync(CancellationToken ct) => Items = await db.Announcements.AsNoTracking()
        .OrderByDescending(x => x.PublishedAt).Take(50).ToListAsync(ct);

    public async Task<IActionResult> OnPostAsync(CancellationToken ct)
    {
        if (!ModelState.IsValid) { await OnGetAsync(ct); return Page(); }
        var actor = Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
        var announcement = new Announcement
        {
            Title = Input.Title.Trim(),
            Body = Input.Body.Trim(),
            Audience = Enum.Parse<AnnouncementAudience>(Input.Audience, true),
            AudienceValue = string.IsNullOrWhiteSpace(Input.AudienceValue) ? null : Input.AudienceValue.Trim(),
            Priority = Input.Priority,
            CreatedBy = actor
        };
        db.Announcements.Add(announcement);
        db.OutboxMessages.Add(new OutboxMessage
        {
            Topic = "bma.push.notification",
            MessageKey = announcement.Id.ToString(),
            PayloadJson = JsonSerializer.Serialize(new
            {
                announcement.Id,
                announcement.Title,
                announcement.Audience,
                announcement.AudienceValue,
                announcement.Priority
            }),
            OccurredAt = announcement.PublishedAt
        });
        audit.Add("ANNOUNCEMENT_PUBLISHED", "ANNOUNCEMENT", announcement.Id.ToString(), actor,
            after: new { announcement.Title, announcement.Audience, announcement.AudienceValue, announcement.Priority });
        await db.SaveChangesAsync(ct);
        return RedirectToPage();
    }

    public async Task<IActionResult> OnPostDeleteAsync(Guid id, CancellationToken ct)
    {
        var announcement = await db.Announcements.SingleOrDefaultAsync(x => x.Id == id, ct);
        if (announcement is null) return NotFound();

        var actor = Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
        var reads = await db.AnnouncementReads
            .Where(x => x.AnnouncementId == id).ToListAsync(ct);
        var pendingPush = await db.OutboxMessages
            .Where(x => x.Topic == "bma.push.notification" &&
                        x.MessageKey == id.ToString() &&
                        x.ProcessedAt == null)
            .ToListAsync(ct);

        db.AnnouncementReads.RemoveRange(reads);
        db.OutboxMessages.RemoveRange(pendingPush);
        db.Announcements.Remove(announcement);
        audit.Add(
            "ANNOUNCEMENT_DELETED",
            "ANNOUNCEMENT",
            announcement.Id.ToString(),
            actor,
            before: new
            {
                announcement.Title,
                announcement.Audience,
                announcement.AudienceValue,
                announcement.Priority
            });
        await db.SaveChangesAsync(ct);
        return RedirectToPage();
    }

    public sealed class AnnouncementInput
    {
        [Required, StringLength(200)] public string Title { get; set; } = "";
        [Required, StringLength(5000)] public string Body { get; set; } = "";
        [RegularExpression("COMPANY|DEPARTMENT|ROLE|PERSON")] public string Audience { get; set; } = "COMPANY";
        [StringLength(100)] public string? AudienceValue { get; set; }
        [RegularExpression("NORMAL|IMPORTANT|EMERGENCY")] public string Priority { get; set; } = "NORMAL";
    }
}
