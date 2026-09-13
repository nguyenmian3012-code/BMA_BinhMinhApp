using Bma.Domain;
using Bma.Modules;

namespace Bma.Api.Tests;

public sealed class PlantStateCalculatorTests
{
    private static readonly DateTimeOffset Now = new(2026, 8, 30, 3, 0, 0, TimeSpan.Zero);

    [Theory]
    [InlineData(true, false, PlantState.Starting)]
    [InlineData(true, true, PlantState.Running)]
    [InlineData(false, true, PlantState.Draining)]
    [InlineData(false, false, PlantState.Stopped)]
    public void Maps_input_and_output_without_declaring_input_off_as_stopped(
        bool inputOn, bool outputOn, PlantState expected)
    {
        var input = Motor("INPUT", inputOn, Now);
        var output = Motor("OUTPUT", outputOn, Now);
        Assert.Equal(expected, PlantStateCalculator.Calculate(input, output, Now, 90));
    }

    [Fact]
    public void Missing_or_stale_heartbeat_is_unknown()
    {
        var input = Motor("INPUT", true, Now.AddMinutes(-5));
        var output = Motor("OUTPUT", true, Now);
        Assert.Equal(PlantState.Unknown, PlantStateCalculator.Calculate(input, output, Now, 90));
        Assert.Equal(PlantState.Unknown, PlantStateCalculator.Calculate(null, output, Now, 90));
    }

    private static MotorStateProjection Motor(string position, bool on, DateTimeOffset heartbeat) => new()
    {
        Position = position,
        MotorId = position,
        IsOn = on,
        HeartbeatAt = heartbeat,
        ChangedAt = heartbeat,
        SourceEventId = $"{position}-{heartbeat:O}"
    };
}
