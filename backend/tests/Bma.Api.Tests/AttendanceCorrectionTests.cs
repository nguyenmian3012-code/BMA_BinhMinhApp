using Bma.Domain;
using Bma.Modules;

namespace Bma.Api.Tests;

public sealed class AttendanceCorrectionTests
{
    private static readonly Guid SessionId = Guid.Parse("11111111-1111-4111-8111-111111111111");
    private static readonly DateTimeOffset ProposedAt =
        new(2026, 9, 30, 6, 30, 0, TimeSpan.FromHours(7));

    [Theory]
    [InlineData("MISSING_ENTRY", AttendanceCorrectionType.MissingEntry)]
    [InlineData("MISSING_EXIT", AttendanceCorrectionType.MissingExit)]
    [InlineData("WRONG_ENTRY", AttendanceCorrectionType.WrongEntry)]
    [InlineData("WRONG_EXIT", AttendanceCorrectionType.WrongExit)]
    public void Accepts_supported_type(string value, AttendanceCorrectionType expected)
    {
        var error = ApiEndpoints.ValidateCorrectionRequest(
            new(SessionId, value, "Máy chưa ghi nhận đúng giờ.", ProposedAt, null), out var actual);

        Assert.Null(error);
        Assert.Equal(expected, actual);
    }

    [Theory]
    [InlineData(null, "Máy chưa ghi nhận đúng giờ.", "CORRECTION_TYPE_INVALID")]
    [InlineData("OTHER", "Máy chưa ghi nhận đúng giờ.", "CORRECTION_TYPE_INVALID")]
    [InlineData("MISSING_ENTRY", "ngắn", "CORRECTION_REASON_TOO_SHORT")]
    public void Rejects_missing_type_or_reason(string? type, string reason, string expected)
    {
        var error = ApiEndpoints.ValidateCorrectionRequest(
            new(SessionId, type, reason, ProposedAt, null), out _);

        Assert.Equal(expected, error);
    }

    [Fact]
    public void Requires_proposed_time()
    {
        var error = ApiEndpoints.ValidateCorrectionRequest(
            new(SessionId, "MISSING_EXIT", "Máy chưa ghi nhận đúng giờ.", null, null), out _);

        Assert.Equal("PROPOSED_TIME_REQUIRED", error);
    }

    [Fact]
    public void State_contract_has_one_initial_and_three_terminal_states()
    {
        Assert.Equal(
            new[] { AttendanceCorrectionStatus.Submitted, AttendanceCorrectionStatus.Approved,
                    AttendanceCorrectionStatus.Rejected, AttendanceCorrectionStatus.Cancelled },
            Enum.GetValues<AttendanceCorrectionStatus>());
    }
}
