using System.ComponentModel.DataAnnotations;
using System.Security.Claims;
using Bma.Data;
using Bma.Domain;
using Bma.Modules;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.EntityFrameworkCore;

namespace Bma.Pages.Admin.Schedules;

[Authorize(Policy = "Admin")]
public sealed class IndexModel(BmaDbContext db, AuditWriter audit) : PageModel
{
    [BindProperty] public ScheduleInput Input { get; set; } = new();
    public List<RunSchedule> Items { get; private set; } = [];

    public async Task OnGetAsync(CancellationToken ct) => Items = await db.RunSchedules.AsNoTracking()
        .OrderByDescending(x => x.PlannedStartAt).Take(100).ToListAsync(ct);

    public async Task<IActionResult> OnPostAsync(CancellationToken ct)
    {
        if (!ModelState.IsValid) { await OnGetAsync(ct); return Page(); }
        var timeZone = TimeZoneInfo.FindSystemTimeZoneById("Asia/Ho_Chi_Minh");
        var unspecified = DateTime.SpecifyKind(Input.PlannedStartLocal, DateTimeKind.Unspecified);
        var schedule = new RunSchedule
        {
            PlannedStartAt = TimeZoneInfo.ConvertTimeToUtc(unspecified, timeZone),
            Status = Input.Status,
            Note = string.IsNullOrWhiteSpace(Input.Note) ? null : Input.Note.Trim(),
            CreatedBy = Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!)
        };
        db.RunSchedules.Add(schedule);
        audit.Add("RUN_SCHEDULE_CREATED", "RUN_SCHEDULE", schedule.Id.ToString(), schedule.CreatedBy,
            after: new { schedule.PlannedStartAt, schedule.Status, schedule.Note });
        await db.SaveChangesAsync(ct);
        return RedirectToPage();
    }

    public sealed class ScheduleInput
    {
        [Required] public DateTime PlannedStartLocal { get; set; } = DateTime.Now.AddDays(1);
        [RegularExpression("PLANNED|CONFIRMED")] public string Status { get; set; } = "PLANNED";
        [StringLength(500)] public string? Note { get; set; }
    }
}
