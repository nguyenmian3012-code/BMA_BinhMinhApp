using System.Security.Claims;
using Bma.Data;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;

namespace Bma.Authentication;

public sealed record RegisterRequest(string Username, string Password, string DisplayName, string? EmployeeCode);
public sealed record LoginRequest(string Username, string Password, string? DeviceName);
public sealed record RefreshRequest(string RefreshToken, string? DeviceName);
public sealed record RevokeRequest(string RefreshToken, string? Reason);

public static class AuthEndpoints
{
    public static IEndpointRouteBuilder MapBmaAuth(this IEndpointRouteBuilder endpoints)
    {
        var group = endpoints.MapGroup("/api/v1/auth").WithTags("Authentication")
            .RequireRateLimiting("auth");

        group.MapPost("/register", async (RegisterRequest request, AuthService auth, CancellationToken ct) =>
        {
            var (created, user) = await auth.RegisterAsync(request.Username, request.Password,
                request.DisplayName, request.EmployeeCode, ct);
            return created
                ? Results.Accepted(value: new { status = "PENDING_APPROVAL", user_id = user!.Id })
                : Results.Conflict(new { error = "USERNAME_EXISTS_OR_INVALID_INPUT" });
        }).AllowAnonymous();

        group.MapPost("/login", async (LoginRequest request, HttpContext http, AuthService auth,
            CancellationToken ct) =>
        {
            var outcome = await auth.LoginAsync(request.Username, request.Password,
                request.DeviceName, http.Connection.RemoteIpAddress?.ToString(), ct);
            return outcome.Status switch
            {
                LoginStatus.Success => Results.Ok(ToResponse(outcome.User!, outcome.Tokens!)),
                LoginStatus.Pending => Results.Json(new { error = "ACCOUNT_PENDING_APPROVAL" }, statusCode: 403),
                LoginStatus.Rejected => Results.Json(new { error = "ACCOUNT_REJECTED" }, statusCode: 403),
                LoginStatus.Disabled => Results.Json(new { error = "ACCOUNT_DISABLED" }, statusCode: 403),
                _ => Results.Unauthorized()
            };
        }).AllowAnonymous();

        group.MapPost("/refresh", async (RefreshRequest request, HttpContext http, AuthService auth,
            CancellationToken ct) =>
        {
            var pair = await auth.RefreshAsync(request.RefreshToken, request.DeviceName,
                http.Connection.RemoteIpAddress?.ToString(), ct);
            return pair is null ? Results.Unauthorized() : Results.Ok(new
            {
                access_token = pair.AccessToken,
                refresh_token = pair.RefreshToken,
                access_expires_at = pair.AccessExpiresAt,
                refresh_expires_at = pair.RefreshExpiresAt
            });
        }).AllowAnonymous();

        group.MapPost("/revoke", async (RevokeRequest request, ClaimsPrincipal user,
            AuthService auth, CancellationToken ct) =>
        {
            var id = UserId(user);
            await auth.RevokeAsync(id, request.RefreshToken,
                string.IsNullOrWhiteSpace(request.Reason) ? "USER_LOGOUT" : request.Reason!, ct);
            return Results.NoContent();
        }).RequireAuthorization();

        group.MapGet("/me", async (ClaimsPrincipal principal, BmaDbContext db,
            CancellationToken ct) =>
        {
            var id = UserId(principal);
            var user = await db.AppUsers.AsNoTracking().SingleAsync(x => x.Id == id, ct);
            return Results.Ok(new
            {
                user.Id,
                user.UserName,
                user.DisplayName,
                user.EmployeeCode,
                status = user.Status.ToString().ToUpperInvariant(),
                roles = AuthService.Roles(user)
            });
        }).RequireAuthorization();

        return endpoints;
    }

    private static object ToResponse(Bma.Domain.AppUser user, TokenPair pair) => new
    {
        access_token = pair.AccessToken,
        refresh_token = pair.RefreshToken,
        access_expires_at = pair.AccessExpiresAt,
        refresh_expires_at = pair.RefreshExpiresAt,
        user = new
        {
            user.Id,
            user.UserName,
            user.DisplayName,
            user.EmployeeCode,
            roles = AuthService.Roles(user)
        }
    };

    private static Guid UserId(ClaimsPrincipal principal) => Guid.Parse(
        principal.FindFirstValue(System.IdentityModel.Tokens.Jwt.JwtRegisteredClaimNames.Sub) ??
        principal.FindFirstValue(ClaimTypes.NameIdentifier) ??
        throw new InvalidOperationException("Authenticated user has no subject claim."));
}
