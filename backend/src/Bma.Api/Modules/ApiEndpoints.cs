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
            var sessions = await db.AttendanceSessions.AsNoTracking()
                .Where(x => x.EmployeeId == employeeCode && x.WorkDate != null)
                .OrderByDescending(x => x.WorkDate)
                .Take(5).Select(x => new
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
                    payroll_approved = x.ApprovedAt != null
                }).ToListAsync(ct);
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
