using System.Security.Claims;
using Bma.Authentication;
using Bma.Data;
using Bma.Domain;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;

namespace Bma.Modules;

public static class ApiEndpoints
{
    public static IEndpointRouteBuilder MapBmaReadApi(this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("/bmapp/api/v1").RequireAuthorization().WithTags("Mobile");

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
            return EtagResults.Json(new { items = rows, generated_at = DateTimeOffset.UtcNow });
        });

        group.MapGet("/recovery/latest", async (RecoveryService service, CancellationToken ct) =>
            EtagResults.Json(await service.GetLatestAsync(ct)));

        group.MapGet("/attendance/me", async (ClaimsPrincipal principal, BmaDbContext db,
            CancellationToken ct) =>
        {
            var userId = UserId(principal);
            var employeeCode = await db.AppUsers.AsNoTracking().Where(x => x.Id == userId)
                .Select(x => x.EmployeeCode).SingleAsync(ct);
            if (string.IsNullOrWhiteSpace(employeeCode))
                return EtagResults.Json(new { items = Array.Empty<object>(), employee_code = employeeCode });
            var sessions = await db.AttendanceSessions.AsNoTracking()
                .Where(x => x.EmployeeId == employeeCode).OrderByDescending(x => x.EntryAt ?? x.ExitAt)
                .Take(60).Select(x => new
                {
                    x.Id,
                    x.EntryAt,
                    x.ExitAt,
                    status = x.Status.ToString().ToUpperInvariant(),
                    x.ReviewReason,
                    payroll_approved = x.ApprovedAt != null
                }).ToListAsync(ct);
            return EtagResults.Json(new { items = sessions, employee_code = employeeCode });
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
                    read_at = reads.GetValueOrDefault(x.Id)
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

    private static Guid UserId(ClaimsPrincipal principal) =>
        Guid.Parse(principal.FindFirstValue(System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Sub) ??
                   principal.FindFirstValue(ClaimTypes.NameIdentifier) ??
                   throw new InvalidOperationException("Authenticated user has no subject claim."));
}
