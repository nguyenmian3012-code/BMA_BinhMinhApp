using System.Text.Json;
using Bma.Data;
using Bma.Domain;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace Bma.Integration;

public sealed class AttendanceReconciliationWorker(
    IServiceScopeFactory scopeFactory,
    IOptions<AttendanceOptions> options,
    ILogger<AttendanceReconciliationWorker> logger) : BackgroundService
{
    private readonly TimeSpan interval = TimeSpan.FromSeconds(
        Math.Clamp(options.Value.ReconciliationSeconds, 15, 3600));

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await Task.Delay(interval, stoppingToken);
        while (!stoppingToken.IsCancellationRequested)
        {
            try { await ReconcileOnceAsync(stoppingToken); }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { break; }
            catch (Exception ex) { logger.LogError(ex, "Attendance reconciliation failed."); }
            await Task.Delay(interval, stoppingToken);
        }
    }

    private async Task ReconcileOnceAsync(CancellationToken ct)
    {
        await using var scope = scopeFactory.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<BmaDbContext>();
        var policy = scope.ServiceProvider.GetRequiredService<AttendancePolicy>();
        await using var transaction = await db.Database.BeginTransactionAsync(ct);
        await db.Database.ExecuteSqlRawAsync("SELECT pg_advisory_xact_lock(4242001)", ct);

        var now = DateTimeOffset.UtcNow;
        var sessions = await db.AttendanceSessions
            .Where(x => x.WorkDate != null && x.Status == AttendanceSessionStatus.Provisional &&
                        x.EntryAt != null && x.ExitAt == null)
            .OrderBy(x => x.WorkDate)
            .Take(500)
            .ToListAsync(ct);
        foreach (var session in sessions.Where(x => policy.CanFinalizeMissingExit(x.WorkDate!.Value, now)))
        {
            session.Status = AttendanceSessionStatus.NeedsReview;
            session.ReviewReason = "MISSING_EXIT";
            session.CreditedMinutes = policy.MissingPunchMinutes;
            db.AuditEntries.Add(new AuditEntry
            {
                Action = "ATTENDANCE_NEEDS_REVIEW",
                SubjectType = "ATTENDANCE_SESSION",
                SubjectId = session.Id.ToString(),
                AfterJson = JsonSerializer.Serialize(new
                {
                    session.EmployeeId,
                    session.WorkDate,
                    session.ReviewReason,
                    session.CreditedMinutes
                })
            });
        }

        await db.SaveChangesAsync(ct);
        await transaction.CommitAsync(ct);
    }
}
