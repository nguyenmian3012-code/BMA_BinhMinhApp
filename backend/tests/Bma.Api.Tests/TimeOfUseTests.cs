using Bma.Modules;

namespace Bma.Api.Tests;

public sealed class TimeOfUseTests
{
    private static readonly TimeSpan Vietnam = TimeSpan.FromHours(7);

    [Theory]
    [InlineData(2026, 8, 31, 10, 0, TimeOfUseBand.Peak)]
    [InlineData(2026, 8, 31, 14, 0, TimeOfUseBand.Normal)]
    [InlineData(2026, 8, 31, 23, 0, TimeOfUseBand.OffPeak)]
    [InlineData(2026, 8, 30, 10, 0, TimeOfUseBand.Normal)]
    public void Classifies_legacy_vietnam_bands(int year, int month, int day, int hour,
        int minute, TimeOfUseBand expected)
    {
        Assert.Equal(expected, LegacyVietnamTimeOfUse.Classify(
            new DateTimeOffset(year, month, day, hour, minute, 0, Vietnam)));
    }

    [Fact]
    public void Splits_across_peak_boundary_without_losing_duration()
    {
        var zone = TimeZoneInfo.CreateCustomTimeZone("VN-Test", Vietnam, "VN", "VN");
        var start = new DateTimeOffset(2026, 8, 31, 9, 0, 0, Vietnam).ToUniversalTime();
        var end = new DateTimeOffset(2026, 8, 31, 12, 0, 0, Vietnam).ToUniversalTime();
        var result = LegacyVietnamTimeOfUse.Split([(start, end)], zone);
        Assert.Equal(TimeSpan.FromHours(2), result.Peak);
        Assert.Equal(TimeSpan.FromHours(1), result.Normal);
        Assert.Equal(TimeSpan.FromHours(3), result.Total);
    }
}
