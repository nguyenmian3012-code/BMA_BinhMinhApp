using Bma.Domain;

namespace Bma.Modules;

public sealed class PlantOptions
{
    public const string Section = "Plant";
    public int HeartbeatStaleSeconds { get; set; } = 90;
    public int OutputStopGraceSeconds { get; set; } = 30;
}

public static class PlantStateCalculator
{
    public static PlantState Calculate(
        MotorStateProjection? input,
        MotorStateProjection? output,
        DateTimeOffset now,
        int staleSeconds)
    {
        if (input is null || output is null) return PlantState.Unknown;
        var staleAfter = TimeSpan.FromSeconds(Math.Clamp(staleSeconds, 15, 600));
        if (now - input.HeartbeatAt > staleAfter || now - output.HeartbeatAt > staleAfter)
            return PlantState.Unknown;
        return (input.IsOn, output.IsOn) switch
        {
            (true, false) => PlantState.Starting,
            (true, true) => PlantState.Running,
            (false, true) => PlantState.Draining,
            _ => PlantState.Stopped
        };
    }

    public static bool CountsAsOperating(PlantState state) =>
        state is PlantState.Starting or PlantState.Running or PlantState.Draining;
}

public enum TimeOfUseBand { Peak, Normal, OffPeak }
public sealed record TimeOfUseBreakdown(TimeSpan Peak, TimeSpan Normal, TimeSpan OffPeak)
{
    public TimeSpan Total => Peak + Normal + OffPeak;
}

public static class LegacyVietnamTimeOfUse
{
    public const string RuleVersion = "VN-LEGACY-3-ZONE-V1";

    public static TimeOfUseBand Classify(DateTimeOffset local)
    {
        var time = TimeOnly.FromDateTime(local.DateTime);
        if (time >= new TimeOnly(22, 0) || time < new TimeOnly(4, 0))
            return TimeOfUseBand.OffPeak;
        var weekday = local.DayOfWeek is not DayOfWeek.Sunday;
        if (weekday &&
            ((time >= new TimeOnly(9, 30) && time < new TimeOnly(11, 30)) ||
             (time >= new TimeOnly(17, 0) && time < new TimeOnly(20, 0))))
            return TimeOfUseBand.Peak;
        return TimeOfUseBand.Normal;
    }

    public static TimeOfUseBreakdown Split(
        IEnumerable<(DateTimeOffset Start, DateTimeOffset End)> periods,
        TimeZoneInfo timeZone)
    {
        var peak = TimeSpan.Zero;
        var normal = TimeSpan.Zero;
        var offPeak = TimeSpan.Zero;
        foreach (var (start, end) in periods.Where(x => x.End > x.Start))
        {
            var cursor = start;
            while (cursor < end)
            {
                var local = TimeZoneInfo.ConvertTime(cursor, timeZone);
                var nextMinute = new DateTimeOffset(local.Year, local.Month, local.Day,
                    local.Hour, local.Minute, 0, local.Offset).AddMinutes(1);
                var nextUtc = nextMinute.ToUniversalTime();
                var segmentEnd = nextUtc < end ? nextUtc : end;
                var duration = segmentEnd - cursor;
                switch (Classify(local))
                {
                    case TimeOfUseBand.Peak: peak += duration; break;
                    case TimeOfUseBand.OffPeak: offPeak += duration; break;
                    default: normal += duration; break;
                }
                cursor = segmentEnd;
            }
        }
        return new(peak, normal, offPeak);
    }
}
