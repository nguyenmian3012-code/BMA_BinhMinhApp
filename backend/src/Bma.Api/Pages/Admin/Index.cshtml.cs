using Bma.Data;
using Bma.Domain;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.EntityFrameworkCore;

namespace Bma.Pages.Admin;

[Authorize(Policy = "Admin")]
public sealed class IndexModel(BmaDbContext db) : PageModel
{
    public int PendingAccounts { get; private set; }
    public int UnprocessedEvents { get; private set; }
    public int FailedEvents { get; private set; }
    public int AttendanceReviews { get; private set; }
    public int PendingPush { get; private set; }

    public async Task OnGetAsync(CancellationToken ct)
    {
        PendingAccounts = await db.AppUsers.CountAsync(x => x.Status == AccountStatus.Pending, ct);
        UnprocessedEvents = await db.OutboxMessages.CountAsync(x =>
            x.Topic == "bma.project.canonical-event" && x.ProcessedAt == null, ct);
        PendingPush = await db.OutboxMessages.CountAsync(x =>
            x.Topic == "bma.push.notification" && x.ProcessedAt == null, ct);
        FailedEvents = await db.RawIntegrationEvents.CountAsync(x =>
            x.ProcessingState == IntegrationProcessingState.Failed, ct);
        AttendanceReviews = await db.AttendanceSessions.CountAsync(x =>
            x.Status == AttendanceSessionStatus.NeedsReview, ct);
    }
}
