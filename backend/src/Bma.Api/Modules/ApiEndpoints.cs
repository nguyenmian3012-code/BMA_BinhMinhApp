using System.Security.Claims;
using Bma.Authentication;
using Bma.Data;
using Bma.Domain;
using Bma.Integration;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;

namespace Bma.Modules;

public sealed record CreateAttendanceCorrectionRequest(
    Guid AttendanceSessionId,
    string? CorrectionType,
    string? Reason,
    DateTimeOffset? ProposedAt,
    string? EvidenceRef);

public sealed record AttendanceCorrectionDecisionRequest(string? Decision, string? Comment);

public static class ApiEndpoints
{
    public static IEndpointRouteBuilder MapBmaReadApi(this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("/api/v1").RequireAuthorization().WithTags("Mobile");

        group.MapGet("/dashboard", async (DashboardService service, CancellationToken ct) =>
            EtagResults.Json(await service.GetAsync(ct)));

        group.MapGet("/quality/latest", async (int? limit, BmaDbContext db, CancellationToken ct) =>
        {
            var rows = await db.QualityReadings.AsNoTracking().OrderByDescending(x => x.MeasuredAt)
                .Take(Math.Clamp(limit ?? 20, 1, 100))
                .Select(x => new
                {
                    x.ResultId,
                    x.LotCode,
                    x.MeasuredAt,
                    x.Ph,
                    x.Whiteness,
                    x.Moisture,
                    x.Fineness,
                    x.FinenessUnit,
                    x.Viscosity,
                    x.ViscosityUnit,
                    x.ExtraValue,
                    freshness = x.MeasuredAt >= DateTimeOffset.UtcNow.AddHours(-4) ? "FRESH" : "STALE"
                }).ToListAsync(ct);
            var snapshotAt = rows.Count == 0
                ? (DateTimeOffset?)null
                : rows.Max(x => x.MeasuredAt);
            return EtagResults.Json(new { items = rows, generated_at = snapshotAt });
        });

        group.MapGet("/recovery/latest", async (RecoveryService service, CancellationToken ct) =>
            EtagResults.Json(await service.GetLatestAsync(ct)));

        group.MapGet("/attendance/me", async (ClaimsPrincipal principal, BmaDbContext db,
            AttendancePolicy attendance, CancellationToken ct) =>
        {
            var userId = UserId(principal);
            var employeeCode = await db.AppUsers.AsNoTracking().Where(x => x.Id == userId)
                .Select(x => x.EmployeeCode).SingleAsync(ct);
            var month = attendance.CurrentMonth(DateTimeOffset.UtcNow);
            if (string.IsNullOrWhiteSpace(employeeCode))
                return EtagResults.Json(new
                {
                    items = Array.Empty<object>(),
                    employee_code = employeeCode,
                    shift_name = attendance.Options.ShiftName,
                    month = month.Key,
                    monthly_total_minutes = 0,
                    monthly_total_hours = 0,
                    monthly_remaining_minutes = 0
                });
            var sessionRows = await db.AttendanceSessions.AsNoTracking()
                .Where(x => x.EmployeeId == employeeCode && x.WorkDate != null)
                .OrderByDescending(x => x.WorkDate)
                .Take(5).ToListAsync(ct);
            var sessions = sessionRows.Select(x => new
                {
                    x.Id,
                    x.WorkDate,
                    x.EntryAt,
                    x.ExitAt,
                    x.ShiftCode,
                    x.CreditedMinutes,
                    status = x.Status == AttendanceSessionStatus.NeedsReview
                        ? "NEEDS_REVIEW"
                        : x.Status.ToString().ToUpperInvariant(),
                    x.ReviewReason,
                    payroll_approved = x.ApprovedAt != null,
                    late_minutes = x.EntryAt is null ? 0 :
                        attendance.CalculateLateMinutes(x.WorkDate!.Value, x.EntryAt.Value),
                    late_duration = AttendancePolicy.Duration(x.EntryAt is null ? 0 :
                        attendance.CalculateLateMinutes(x.WorkDate!.Value, x.EntryAt.Value))
                }).ToList();
            var now = DateTimeOffset.UtcNow;
            var today = attendance.WorkDate(now);
            var todaySession = sessionRows.SingleOrDefault(x => x.WorkDate == today);
            var approvedLeave = todaySession is
                { Status: AttendanceSessionStatus.Approved, ReviewReason: "APPROVED_LEAVE" };
            var presence = attendance.PresenceStatus(
                now, todaySession?.EntryAt, todaySession?.ExitAt, approvedLeave);
            var monthlyTotal = await db.AttendanceSessions.AsNoTracking()
                .Where(x => x.EmployeeId == employeeCode && x.WorkDate != null &&
                            x.WorkDate.Value >= month.Start && x.WorkDate.Value < month.End)
                .Select(x => (int?)x.CreditedMinutes)
                .SumAsync(ct) ?? 0;
            return EtagResults.Json(new
            {
                items = sessions,
                employee_code = employeeCode,
                shift_name = attendance.Options.ShiftName,
                presence_status = presence.ToString().ToUpperInvariant(),
                month = month.Key,
                monthly_total_minutes = monthlyTotal,
                monthly_total_hours = monthlyTotal / 60,
                monthly_remaining_minutes = monthlyTotal % 60
            });
        });

        group.MapPost("/attendance/corrections", async (CreateAttendanceCorrectionRequest request,
            ClaimsPrincipal principal, BmaDbContext db, AuditWriter audit, CancellationToken ct) =>
        {
            var error = ValidateCorrectionRequest(request, out var correctionType);
            if (error is not null) return Results.BadRequest(new { error });

            var userId = UserId(principal);
            var employeeCode = await db.AppUsers.AsNoTracking().Where(x => x.Id == userId)
                .Select(x => x.EmployeeCode).SingleAsync(ct);
            if (string.IsNullOrWhiteSpace(employeeCode))
                return Results.Conflict(new { error = "EMPLOYEE_PROFILE_NOT_LINKED" });

            var session = await db.AttendanceSessions.AsNoTracking().SingleOrDefaultAsync(
                x => x.Id == request.AttendanceSessionId && x.EmployeeId == employeeCode, ct);
            if (session is null) return Results.NotFound(new { error = "ATTENDANCE_SESSION_NOT_FOUND" });

            var duplicate = await db.AttendanceCorrectionRequests.AsNoTracking().AnyAsync(
                x => x.AttendanceSessionId == session.Id &&
                     x.CorrectionType == correctionType &&
                     x.Status == AttendanceCorrectionStatus.Submitted, ct);
            if (duplicate) return Results.Conflict(new { error = "CORRECTION_ALREADY_SUBMITTED" });

            var correction = new AttendanceCorrectionRequest
            {
                AttendanceSessionId = session.Id,
                EmployeeId = employeeCode,
                CorrectionType = correctionType,
                Reason = request.Reason!.Trim(),
                ProposedAt = request.ProposedAt!.Value,
                EvidenceRef = string.IsNullOrWhiteSpace(request.EvidenceRef)
                    ? null
                    : request.EvidenceRef.Trim(),
                RequestedBy = userId
            };
            db.AttendanceCorrectionRequests.Add(correction);
            audit.Add("ATTENDANCE_CORRECTION_SUBMITTED", "ATTENDANCE_CORRECTION",
                correction.Id.ToString(), userId, after: new
                {
                    correction.AttendanceSessionId,
                    correction.EmployeeId,
                    correction_type = CorrectionTypeCode(correction.CorrectionType),
                    correction.ProposedAt,
                    correction.Reason,
                    status = "SUBMITTED"
                });
            await db.SaveChangesAsync(ct);

            return Results.Created($"/api/v1/attendance/corrections/{correction.Id}", new
            {
                correction.Id,
                correction.AttendanceSessionId,
                correction.EmployeeId,
                correction_type = CorrectionTypeCode(correction.CorrectionType),
                correction.ProposedAt,
                correction.Reason,
                correction.EvidenceRef,
                status = correction.Status.ToString().ToUpperInvariant(),
                correction.RequestedAt
            });
        });

        group.MapGet("/attendance/corrections/pending", async (ClaimsPrincipal principal,
            BmaDbContext db, CancellationToken ct) =>
        {
            var reviewer = await db.AppUsers.AsNoTracking().SingleAsync(x => x.Id == UserId(principal), ct);
            var roles = AuthService.Roles(reviewer);
            var canReviewAll = roles.Contains("Admin", StringComparer.OrdinalIgnoreCase) ||
                               roles.Contains("HR", StringComparer.OrdinalIgnoreCase);
            var query = from correction in db.AttendanceCorrectionRequests.AsNoTracking()
                        join employee in db.EmployeeProfiles.AsNoTracking()
                            on correction.EmployeeId equals employee.EmployeeCode
                        where correction.Status == AttendanceCorrectionStatus.Submitted &&
                              (canReviewAll || employee.ManagerEmployeeCode == reviewer.EmployeeCode)
                        orderby correction.RequestedAt
                        select new
                        {
                            correction.Id,
                            correction.AttendanceSessionId,
                            correction.EmployeeId,
                            employee.FullName,
                            correction.CorrectionType,
                            correction.Reason,
                            correction.ProposedAt,
                            correction.EvidenceRef,
                            correction.RequestedAt
                        };
            var pending = await query.Take(100).ToListAsync(ct);
            return Results.Ok(new
            {
                items = pending.Select(x => new
                {
                    x.Id,
                    x.AttendanceSessionId,
                    x.EmployeeId,
                    x.FullName,
                    correction_type = CorrectionTypeCode(x.CorrectionType),
                    x.Reason,
                    x.ProposedAt,
                    x.EvidenceRef,
                    status = "SUBMITTED",
                    x.RequestedAt
                })
            });
        }).RequireAuthorization("AttendanceReviewer");

        group.MapPost("/attendance/corrections/{id:guid}/decision", async (Guid id,
            AttendanceCorrectionDecisionRequest request, ClaimsPrincipal principal,
            BmaDbContext db, AttendancePolicy attendance, AuditWriter audit, CancellationToken ct) =>
        {
            var error = ValidateCorrectionDecision(request, out var approve);
            if (error is not null) return Results.BadRequest(new { error });

            var reviewerId = UserId(principal);
            var reviewer = await db.AppUsers.AsNoTracking().SingleAsync(x => x.Id == reviewerId, ct);
            await using var transaction = await db.Database.BeginTransactionAsync(ct);
            var correction = await db.AttendanceCorrectionRequests
                .FromSqlInterpolated($"SELECT * FROM attendance_correction_requests WHERE id = {id} FOR UPDATE")
                .SingleOrDefaultAsync(ct);
            if (correction is null) return Results.NotFound(new { error = "CORRECTION_NOT_FOUND" });
            if (correction.Status != AttendanceCorrectionStatus.Submitted)
                return Results.Conflict(new { error = "CORRECTION_ALREADY_DECIDED" });

            var target = await db.EmployeeProfiles.AsNoTracking()
                .SingleOrDefaultAsync(x => x.EmployeeCode == correction.EmployeeId, ct);
            if (target is null || !CanReviewAttendanceCorrection(
                    AuthService.Roles(reviewer), reviewer.EmployeeCode, target.ManagerEmployeeCode))
                return Results.Forbid();

            var session = await db.AttendanceSessions
                .FromSqlInterpolated($"SELECT * FROM attendance_sessions WHERE id = {correction.AttendanceSessionId} FOR UPDATE")
                .SingleAsync(ct);
            var before = new
            {
                correction_status = correction.Status.ToString().ToUpperInvariant(),
                session.EntryAt,
                session.ExitAt,
                session.CreditedMinutes,
                session_status = session.Status.ToString().ToUpperInvariant(),
                session.ReviewReason
            };

            if (approve)
            {
                ApplyApprovedCorrection(correction, session, attendance);
                if (session.EntryAt is not null && session.ExitAt is not null &&
                    session.ExitAt <= session.EntryAt)
                    return Results.Conflict(new { error = "CORRECTION_TIME_ORDER_INVALID" });
                correction.Status = AttendanceCorrectionStatus.Approved;
            }
            else
            {
                correction.Status = AttendanceCorrectionStatus.Rejected;
            }
            correction.ReviewedBy = reviewerId;
            correction.ReviewedAt = DateTimeOffset.UtcNow;
            correction.ReviewComment = request.Comment!.Trim();

            var action = approve ? "ATTENDANCE_CORRECTION_APPROVED" : "ATTENDANCE_CORRECTION_REJECTED";
            audit.Add(action, "ATTENDANCE_CORRECTION", correction.Id.ToString(), reviewerId,
                before: before, after: new
                {
                    correction_status = correction.Status.ToString().ToUpperInvariant(),
                    reason = correction.ReviewComment,
                    session.EntryAt,
                    session.ExitAt,
                    session.CreditedMinutes,
                    session_status = session.Status.ToString().ToUpperInvariant(),
                    session.ReviewReason
            });
            await db.SaveChangesAsync(ct);
            await transaction.CommitAsync(ct);
            return Results.Ok(new
            {
                correction.Id,
                status = correction.Status.ToString().ToUpperInvariant(),
                correction.ReviewedAt,
                correction.ReviewComment,
                attendance_session = new
                {
                    session.Id,
                    session.EntryAt,
                    session.ExitAt,
                    session.CreditedMinutes,
                    status = session.Status.ToString().ToUpperInvariant(),
                    session.ReviewReason
                }
            });
        }).RequireAuthorization("AttendanceReviewer");

        group.MapGet("/profile/me", async (ClaimsPrincipal principal, BmaDbContext db,
            CancellationToken ct) =>
        {
            var userId = UserId(principal);
            var profile = await db.EmployeeProfiles.AsNoTracking()
                .Where(x => x.UserId == userId).Select(x => new
                {
                    x.EmployeeCode,
                    x.FullName,
                    x.Department,
                    x.Position,
                    x.HiredOn,
                    x.IsActive,
                    x.ManagerEmployeeCode,
                    x.Responsibilities,
                    x.Obligations,
                    x.Benefits,
                    x.Accountabilities,
                    x.EffectiveFrom,
                    x.Version,
                    x.UpdatedAt
                }).SingleOrDefaultAsync(ct);
            return profile is null
                ? Results.NotFound(new { error = "EMPLOYEE_PROFILE_NOT_LINKED" })
                : EtagResults.Json(profile, 60);
        });

        group.MapGet("/announcements", async (ClaimsPrincipal principal, BmaDbContext db,
            CancellationToken ct) =>
        {
            var userId = UserId(principal);
            var user = await db.AppUsers.AsNoTracking().SingleAsync(x => x.Id == userId, ct);
            var profile = await db.EmployeeProfiles.AsNoTracking().SingleOrDefaultAsync(x => x.UserId == userId, ct);
            var roles = AuthService.Roles(user);
            var now = DateTimeOffset.UtcNow;
            var candidates = await db.Announcements.AsNoTracking()
                .Where(x => x.PublishedAt <= now && (x.ExpiresAt == null || x.ExpiresAt > now))
                .OrderByDescending(x => x.PublishedAt).Take(200).ToListAsync(ct);
            var allowed = candidates.Where(x => x.Audience switch
            {
                AnnouncementAudience.Company => true,
                AnnouncementAudience.Person => x.AudienceValue == user.Id.ToString() ||
                                                  x.AudienceValue == user.EmployeeCode,
                AnnouncementAudience.Department => x.AudienceValue == profile?.Department,
                AnnouncementAudience.Role => roles.Contains(x.AudienceValue ?? "", StringComparer.OrdinalIgnoreCase),
                _ => false
            }).Take(50).ToList();
            var ids = allowed.Select(x => x.Id).ToList();
            var reads = await db.AnnouncementReads.AsNoTracking()
                .Where(x => x.UserId == userId && ids.Contains(x.AnnouncementId))
                .ToDictionaryAsync(x => x.AnnouncementId, x => x.ReadAt, ct);
            return EtagResults.Json(new
            {
                items = allowed.Select(x => new
                {
                    x.Id,
                    x.Title,
                    x.Body,
                    priority = x.Priority,
                    x.PublishedAt,
                    x.ExpiresAt,
                    read_at = AnnouncementReadAt(reads, x.Id)
                })
            });
        });

        group.MapPost("/announcements/{id:guid}/read", async (Guid id, ClaimsPrincipal principal,
            BmaDbContext db, CancellationToken ct) =>
        {
            var userId = UserId(principal);
            if (!await db.Announcements.AnyAsync(x => x.Id == id, ct)) return Results.NotFound();
            if (!await db.AnnouncementReads.AnyAsync(x => x.AnnouncementId == id && x.UserId == userId, ct))
            {
                db.AnnouncementReads.Add(new AnnouncementRead { AnnouncementId = id, UserId = userId });
                await db.SaveChangesAsync(ct);
            }
            return Results.NoContent();
        });

        return endpoints;
    }

    public static DateTimeOffset? AnnouncementReadAt(
        IReadOnlyDictionary<Guid, DateTimeOffset> reads, Guid announcementId) =>
        reads.TryGetValue(announcementId, out var readAt) ? readAt : null;

    public static string? ValidateCorrectionRequest(
        CreateAttendanceCorrectionRequest request,
        out AttendanceCorrectionType correctionType)
    {
        correctionType = default;
        if (request.AttendanceSessionId == Guid.Empty) return "ATTENDANCE_SESSION_REQUIRED";
        if (!TryCorrectionType(request.CorrectionType, out correctionType))
            return "CORRECTION_TYPE_INVALID";
        if (string.IsNullOrWhiteSpace(request.Reason) || request.Reason.Trim().Length < 10)
            return "CORRECTION_REASON_TOO_SHORT";
        if (request.Reason.Trim().Length > 500) return "CORRECTION_REASON_TOO_LONG";
        if (request.ProposedAt is null) return "PROPOSED_TIME_REQUIRED";
        if (request.EvidenceRef is { } evidence && evidence.Trim().Length > 500)
            return "EVIDENCE_REF_TOO_LONG";
        return null;
    }

    public static string? ValidateCorrectionDecision(
        AttendanceCorrectionDecisionRequest request,
        out bool approve)
    {
        approve = string.Equals(request.Decision?.Trim(), "APPROVE", StringComparison.OrdinalIgnoreCase);
        if (!approve && !string.Equals(request.Decision?.Trim(), "REJECT", StringComparison.OrdinalIgnoreCase))
            return "CORRECTION_DECISION_INVALID";
        if (string.IsNullOrWhiteSpace(request.Comment) || request.Comment.Trim().Length < 10)
            return "CORRECTION_COMMENT_TOO_SHORT";
        if (request.Comment.Trim().Length > 500) return "CORRECTION_COMMENT_TOO_LONG";
        return null;
    }

    public static bool CanReviewAttendanceCorrection(
        IEnumerable<string> roles,
        string? reviewerEmployeeCode,
        string? managerEmployeeCode)
    {
        var set = roles.ToHashSet(StringComparer.OrdinalIgnoreCase);
        if (set.Contains("Admin") || set.Contains("HR")) return true;
        return (set.Contains("Operations") || set.Contains("Executive") || set.Contains("Manager")) &&
               !string.IsNullOrWhiteSpace(reviewerEmployeeCode) &&
               string.Equals(reviewerEmployeeCode, managerEmployeeCode, StringComparison.OrdinalIgnoreCase);
    }

    public static void ApplyApprovedCorrection(
        AttendanceCorrectionRequest correction,
        AttendanceSession session,
        AttendancePolicy attendance)
    {
        if (correction.CorrectionType is AttendanceCorrectionType.MissingEntry or AttendanceCorrectionType.WrongEntry)
            session.EntryAt = correction.ProposedAt;
        else
            session.ExitAt = correction.ProposedAt;

        if (session.EntryAt is not null && session.ExitAt is not null && session.WorkDate is not null)
        {
            session.CreditedMinutes = attendance.CalculateCreditedMinutes(
                session.WorkDate.Value, session.EntryAt.Value, session.ExitAt.Value);
            session.Status = AttendanceSessionStatus.Confirmed;
            session.ReviewReason = null;
        }
        else
        {
            session.CreditedMinutes = attendance.MissingPunchMinutes;
            session.Status = AttendanceSessionStatus.NeedsReview;
            session.ReviewReason = session.EntryAt is null ? "MISSING_ENTRY" : "MISSING_EXIT";
        }
    }

    private static bool TryCorrectionType(string? value, out AttendanceCorrectionType type)
    {
        type = value?.Trim().ToUpperInvariant() switch
        {
            "MISSING_ENTRY" => AttendanceCorrectionType.MissingEntry,
            "MISSING_EXIT" => AttendanceCorrectionType.MissingExit,
            "WRONG_ENTRY" => AttendanceCorrectionType.WrongEntry,
            "WRONG_EXIT" => AttendanceCorrectionType.WrongExit,
            _ => default
        };
        return value?.Trim().ToUpperInvariant() is
            "MISSING_ENTRY" or "MISSING_EXIT" or "WRONG_ENTRY" or "WRONG_EXIT";
    }

    private static string CorrectionTypeCode(AttendanceCorrectionType type) => type switch
    {
        AttendanceCorrectionType.MissingEntry => "MISSING_ENTRY",
        AttendanceCorrectionType.MissingExit => "MISSING_EXIT",
        AttendanceCorrectionType.WrongEntry => "WRONG_ENTRY",
        AttendanceCorrectionType.WrongExit => "WRONG_EXIT",
        _ => throw new ArgumentOutOfRangeException(nameof(type))
    };

    private static Guid UserId(ClaimsPrincipal principal) =>
        Guid.Parse(principal.FindFirstValue(System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Sub) ??
                   principal.FindFirstValue(ClaimTypes.NameIdentifier) ??
                   throw new InvalidOperationException("Authenticated user has no subject claim."));
}
