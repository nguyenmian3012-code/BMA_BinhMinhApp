using System.Globalization;
using Microsoft.Extensions.Options;

namespace Bma.Integration;

public sealed class AttendanceOptions
{
    public const string Section = "Attendance";
    public string TimeZone { get; set; } = "Asia/Ho_Chi_Minh";
    public string ShiftCode { get; set; } = "ADMIN";
    public string ShiftName { get; set; } = "Ca Hành Chính";
    public string ShiftStart { get; set; } = "07:00";
    public string ShiftEnd { get; set; } = "17:00";
    public string BreakStart { get; set; } = "11:00";
    public string BreakEnd { get; set; } = "13:00";
    public int EarlyEntryMinutes { get; set; } = 30;
    public int LateExitMinutes { get; set; } = 20;
    public int MissingPunchPercent { get; set; } = 50;
    public int ReconciliationSeconds { get; set; } = 60;
}

public enum AttendanceScanWindow { Entry, Exit, Break, OutsideShift, NonWorkingDay }

public sealed record AttendanceScanDecision(
    DateOnly WorkDate,
    AttendanceScanWindow Window,
    DateTimeOffset LocalTime);

public sealed class AttendancePolicy
{
    private static readonly HashSet<DayOfWeek> WorkDays =
    [
        DayOfWeek.Monday,
        DayOfWeek.Tuesday,
        DayOfWeek.Wednesday,
        DayOfWeek.Thursday,
        DayOfWeek.Friday,
        DayOfWeek.Saturday
    ];

    private readonly TimeZoneInfo timeZone;
    private readonly TimeOnly shiftStart;
    private readonly TimeOnly shiftEnd;
    private readonly TimeOnly breakStart;
    private readonly TimeOnly breakEnd;
    private readonly TimeOnly firstEntry;
    private readonly TimeOnly lastExit;

    public AttendancePolicy(IOptions<AttendanceOptions> configured)
    {
        Options = configured.Value;
        timeZone = TimeZoneInfo.FindSystemTimeZoneById(Options.TimeZone);
        shiftStart = ParseTime(Options.ShiftStart, nameof(Options.ShiftStart));
        shiftEnd = ParseTime(Options.ShiftEnd, nameof(Options.ShiftEnd));
        breakStart = ParseTime(Options.BreakStart, nameof(Options.BreakStart));
        breakEnd = ParseTime(Options.BreakEnd, nameof(Options.BreakEnd));
        if (!(shiftStart < breakStart && breakStart < breakEnd && breakEnd < shiftEnd))
            throw new InvalidOperationException("Attendance shift must be same-day and contain its unpaid break.");
        if (Options.EarlyEntryMinutes is < 0 or > 240 || Options.LateExitMinutes is < 0 or > 240)
            throw new InvalidOperationException("Attendance early/late windows must be between 0 and 240 minutes.");
        if (Options.MissingPunchPercent is < 0 or > 100)
            throw new InvalidOperationException("Attendance missing punch percent must be between 0 and 100.");
        firstEntry = shiftStart.AddMinutes(-Options.EarlyEntryMinutes);
        lastExit = shiftEnd.AddMinutes(Options.LateExitMinutes);
    }

    public AttendanceOptions Options { get; }
    public int ScheduledMinutes =>
        (int)(shiftEnd - shiftStart).TotalMinutes - (int)(breakEnd - breakStart).TotalMinutes;
    public int MissingPunchMinutes => ScheduledMinutes * Options.MissingPunchPercent / 100;

    public AttendanceScanDecision Classify(DateTimeOffset occurredAt)
    {
        var local = TimeZoneInfo.ConvertTime(occurredAt, timeZone);
        var date = DateOnly.FromDateTime(local.DateTime);
        if (!WorkDays.Contains(local.DayOfWeek))
            return new(date, AttendanceScanWindow.NonWorkingDay, local);

        var time = TimeOnly.FromDateTime(local.DateTime);
        var window = time >= firstEntry && time < breakStart
            ? AttendanceScanWindow.Entry
            : time >= breakStart && time < breakEnd
                ? AttendanceScanWindow.Break
                : time >= breakEnd && time <= lastExit
                    ? AttendanceScanWindow.Exit
                    : AttendanceScanWindow.OutsideShift;
        return new(date, window, local);
    }

    public int CalculateCreditedMinutes(
        DateOnly workDate,
        DateTimeOffset entryAt,
        DateTimeOffset exitAt)
    {
        var start = Max(entryAt, ToUtc(workDate, shiftStart));
        var end = Min(exitAt, ToUtc(workDate, shiftEnd));
        if (end <= start) return 0;

        var credited = end - start;
        var unpaidStart = Max(start, ToUtc(workDate, breakStart));
        var unpaidEnd = Min(end, ToUtc(workDate, breakEnd));
        if (unpaidEnd > unpaidStart) credited -= unpaidEnd - unpaidStart;
        return Math.Clamp((int)Math.Floor(credited.TotalMinutes), 0, ScheduledMinutes);
    }

    public bool CanFinalizeMissingExit(DateOnly workDate, DateTimeOffset now) =>
        now >= ToUtc(workDate, lastExit).AddMinutes(10);

    public (DateOnly Start, DateOnly End, string Key) CurrentMonth(DateTimeOffset now)
    {
        var local = TimeZoneInfo.ConvertTime(now, timeZone);
        var startDate = new DateOnly(local.Year, local.Month, 1);
        var endDate = startDate.AddMonths(1);
        return (startDate, endDate, $"{local.Year:D4}-{local.Month:D2}");
    }

    private DateTimeOffset ToUtc(DateOnly date, TimeOnly time)
    {
        var local = DateTime.SpecifyKind(date.ToDateTime(time), DateTimeKind.Unspecified);
        return new DateTimeOffset(TimeZoneInfo.ConvertTimeToUtc(local, timeZone), TimeSpan.Zero);
    }

    private static TimeOnly ParseTime(string value, string name) =>
        TimeOnly.TryParseExact(value, "HH:mm", CultureInfo.InvariantCulture,
            DateTimeStyles.None, out var parsed)
            ? parsed
            : throw new InvalidOperationException($"Attendance {name} must use HH:mm.");

    private static DateTimeOffset Max(DateTimeOffset left, DateTimeOffset right) =>
        left >= right ? left : right;
    private static DateTimeOffset Min(DateTimeOffset left, DateTimeOffset right) =>
        left <= right ? left : right;
}
