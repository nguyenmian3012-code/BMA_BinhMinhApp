using Bma.Integration;
using Microsoft.Extensions.Options;

namespace Bma.Api.Tests;

public sealed class AttendancePolicyTests
{
    private readonly AttendancePolicy policy = new(Options.Create(new AttendanceOptions()));

    [Theory]
    [InlineData("2026-09-07T00:00:00Z", AttendanceScanWindow.Entry)]
    [InlineData("2026-09-07T04:30:00Z", AttendanceScanWindow.Break)]
    [InlineData("2026-09-07T06:00:00Z", AttendanceScanWindow.Exit)]
    [InlineData("2026-09-07T10:20:00Z", AttendanceScanWindow.Exit)]
    [InlineData("2026-09-07T10:21:00Z", AttendanceScanWindow.OutsideShift)]
    [InlineData("2026-09-06T00:00:00Z", AttendanceScanWindow.NonWorkingDay)]
    public void Classifies_scan_by_vietnam_shift(string timestamp, AttendanceScanWindow expected)
    {
        var result = policy.Classify(DateTimeOffset.Parse(timestamp));
        Assert.Equal(expected, result.Window);
    }

    [Fact]
    public void Full_shift_excludes_two_hour_lunch()
    {
        var date = new DateOnly(2026, 9, 7);
        var credited = policy.CalculateCreditedMinutes(
            date,
            DateTimeOffset.Parse("2026-09-06T23:30:00Z"),
            DateTimeOffset.Parse("2026-09-07T10:20:00Z"));

        Assert.Equal(480, credited);
        Assert.Equal(240, policy.MissingPunchMinutes);
    }

    [Fact]
    public void Late_entry_is_credited_only_for_actual_paid_minutes()
    {
        var credited = policy.CalculateCreditedMinutes(
            new DateOnly(2026, 9, 7),
            DateTimeOffset.Parse("2026-09-07T01:00:00Z"),
            DateTimeOffset.Parse("2026-09-07T10:00:00Z"));

        Assert.Equal(420, credited);
    }
}
