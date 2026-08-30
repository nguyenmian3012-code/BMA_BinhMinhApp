using Bma.Data;
using Bma.Domain;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace Bma.Modules;

public sealed record DashboardReadModel(
    string PlantState,
    DateTimeOffset? RunningSince,
    DateTimeOffset? LastStoppedAt,
    DateTimeOffset? NextPlannedStart,
    decimal MonthOperatingHours,
    decimal PeakHours,
    decimal NormalHours,
    decimal OffPeakHours,
    string TimeOfUseRuleVersion,
    DateTimeOffset GeneratedAt,
    bool IsStale);

public sealed record RecoveryReadModel(
    string Status,
    decimal? ValuePercent,
    string? PeriodId,
    string? Basis,
    string? FormulaVersion,
    decimal? InputKg,
    decimal? OutputKg,
    DateTimeOffset GeneratedAt);

public sealed class DashboardService(
    BmaDbContext db,
    IOptions<PlantOptions> options,
    IConfiguration configuration)
{
    private readonly PlantOptions plant = options.Value;

    public async Task<DashboardReadModel> GetAsync(CancellationToken ct)
    {
        var now = DateTimeOffset.UtcNow;
        var timeZoneName = configuration["TimeOfUse:TimeZone"] ?? "Asia/Ho_Chi_Minh";
        var timeZone = TimeZoneInfo.FindSystemTimeZoneById(timeZoneName);
        var local = TimeZoneInfo.ConvertTime(now, timeZone);
        var localMonth = new DateTimeOffset(local.Year, local.Month, 1, 0, 0, 0, local.Offset);
        var monthStart = localMonth.ToUniversalTime();
        var motors = await db.MotorStateProjections.AsNoTracking().ToListAsync(ct);
        var input = motors.SingleOrDefault(x => x.Position == "INPUT");
        var output = motors.SingleOrDefault(x => x.Position == "OUTPUT");
        var current = PlantStateCalculator.Calculate(input, output, now, plant.HeartbeatStaleSeconds);
        var periods = await db.PlantStatePeriods.AsNoTracking()
            .Where(x => x.StartedAt < now && (x.EndedAt == null || x.EndedAt > monthStart))
            .OrderBy(x => x.StartedAt).ToListAsync(ct);
        var lastSafeHeartbeat = input is null || output is null
            ? monthStart
            : (input.HeartbeatAt < output.HeartbeatAt ? input.HeartbeatAt : output.HeartbeatAt)
                .AddSeconds(Math.Clamp(plant.HeartbeatStaleSeconds, 15, 600));
        var operating = periods
            .Where(x => PlantStateCalculator.CountsAsOperating(x.State))
            .Select(x =>
            {
                var start = x.StartedAt < monthStart ? monthStart : x.StartedAt;
                var end = x.EndedAt ?? now;
                if (x.EndedAt is null && end > lastSafeHeartbeat) end = lastSafeHeartbeat;
                return (Start: start, End: end < start ? start : end);
            }).ToList();
        var breakdown = LegacyVietnamTimeOfUse.Split(operating, timeZone);
        var open = periods.LastOrDefault(x => x.EndedAt is null);
        var lastStopped = await db.PlantStatePeriods.AsNoTracking()
            .Where(x => x.State == PlantState.Stopped)
            .OrderByDescending(x => x.StartedAt).Select(x => (DateTimeOffset?)x.StartedAt)
            .FirstOrDefaultAsync(ct);
        var nextStart = await db.RunSchedules.AsNoTracking()
            .Where(x => (x.Status == "PLANNED" || x.Status == "CONFIRMED") && x.PlannedStartAt >= now)
            .OrderBy(x => x.PlannedStartAt).Select(x => (DateTimeOffset?)x.PlannedStartAt)
            .FirstOrDefaultAsync(ct);
        return new(
            current.ToString().ToUpperInvariant(),
            open is not null && PlantStateCalculator.CountsAsOperating(open.State) ? open.StartedAt : null,
            lastStopped,
            nextStart,
            Hours(breakdown.Total),
            Hours(breakdown.Peak),
            Hours(breakdown.Normal),
            Hours(breakdown.OffPeak),
            configuration["TimeOfUse:RuleVersion"] ?? LegacyVietnamTimeOfUse.RuleVersion,
            now,
            current == PlantState.Unknown);
    }

    private static decimal Hours(TimeSpan value) => Math.Round((decimal)value.TotalHours, 2);
}

public sealed class RecoveryService(BmaDbContext db)
{
    public async Task<RecoveryReadModel> GetLatestAsync(CancellationToken ct)
    {
        var now = DateTimeOffset.UtcNow;
        var latest = await db.ProductionMassReadings.AsNoTracking()
            .Where(x => x.Approved).OrderByDescending(x => x.RecordedAt).FirstOrDefaultAsync(ct);
        if (latest is null)
            return new("INSUFFICIENT_DATA", null, null, null, null, null, null, now);
        var rows = await db.ProductionMassReadings.AsNoTracking()
            .Where(x => x.Approved && x.PeriodId == latest.PeriodId &&
                        x.Basis == latest.Basis && x.FormulaVersion == latest.FormulaVersion)
            .ToListAsync(ct);
        var input = rows.Where(x => x.Kind == ProductionMassKind.CassavaInput).Sum(x => x.MassKg);
        var output = rows.Where(x => x.Kind == ProductionMassKind.StarchOutput).Sum(x => x.MassKg);
        if (input <= 0 || output <= 0)
            return new("INSUFFICIENT_DATA", null, latest.PeriodId,
                latest.Basis.ToString().ToUpperInvariant(), latest.FormulaVersion,
                input > 0 ? input : null, output > 0 ? output : null, now);
        return new("AVAILABLE", Math.Round(output / input * 100m, 2), latest.PeriodId,
            latest.Basis.ToString().ToUpperInvariant(), latest.FormulaVersion, input, output, now);
    }
}
