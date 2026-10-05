using Bma.Domain;
using Bma.Modules;
using Bma.Integration;
using Microsoft.Extensions.Options;

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

    [Theory]
    [InlineData("APPROVE", true)]
    [InlineData("REJECT", false)]
    public void Accepts_review_decisions_with_comment(string decision, bool expectedApprove)
    {
        var error = ApiEndpoints.ValidateCorrectionDecision(
            new(decision, "Đã đối chiếu với quản lý ca."), out var approve);

        Assert.Null(error);
        Assert.Equal(expectedApprove, approve);
    }

    [Theory]
    [InlineData("OTHER", "Đã đối chiếu với quản lý ca.", "CORRECTION_DECISION_INVALID")]
    [InlineData("APPROVE", "ngắn", "CORRECTION_COMMENT_TOO_SHORT")]
    public void Rejects_invalid_review_decision(string decision, string comment, string expected)
    {
        var error = ApiEndpoints.ValidateCorrectionDecision(new(decision, comment), out _);

        Assert.Equal(expected, error);
    }

    [Fact]
    public void Reviewer_scope_allows_hr_and_direct_manager_only()
    {
        Assert.True(ApiEndpoints.CanReviewAttendanceCorrection(["HR"], null, null));
        Assert.True(ApiEndpoints.CanReviewAttendanceCorrection(["Operations"], "BM002", "BM002"));
        Assert.False(ApiEndpoints.CanReviewAttendanceCorrection(["Operations"], "BM003", "BM002"));
        Assert.False(ApiEndpoints.CanReviewAttendanceCorrection(["Employee"], "BM002", "BM002"));
    }

    [Fact]
    public void Approved_entry_correction_recalculates_derived_session()
    {
        var policy = new AttendancePolicy(Options.Create(new AttendanceOptions()));
        var session = new AttendanceSession
        {
            EmployeeId = "BM001",
            WorkDate = new DateOnly(2026, 9, 30),
            EntryAt = new DateTimeOffset(2026, 9, 30, 0, 0, 0, TimeSpan.Zero),
            ExitAt = new DateTimeOffset(2026, 9, 30, 10, 0, 0, TimeSpan.Zero),
            Status = AttendanceSessionStatus.Confirmed
        };
        var correction = new AttendanceCorrectionRequest
        {
            AttendanceSessionId = session.Id,
            EmployeeId = "BM001",
            CorrectionType = AttendanceCorrectionType.WrongEntry,
            Reason = "Terminal recorded the wrong entry time.",
            ProposedAt = new DateTimeOffset(2026, 9, 30, 0, 30, 0, TimeSpan.Zero),
            RequestedBy = Guid.NewGuid()
        };

        ApiEndpoints.ApplyApprovedCorrection(correction, session, policy);

        Assert.Equal(450, session.CreditedMinutes);
        Assert.Equal(AttendanceSessionStatus.Confirmed, session.Status);
        Assert.Null(session.ReviewReason);
    }
}
