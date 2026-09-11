using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Bma.Data;
using Bma.Domain;
using Bma.Modules;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;

namespace Bma.Authentication;

public enum LoginStatus { Success, InvalidCredentials, Pending, Rejected, Disabled }

public sealed record TokenPair(
    string AccessToken,
    string RefreshToken,
    DateTimeOffset AccessExpiresAt,
    DateTimeOffset RefreshExpiresAt);

public sealed record LoginOutcome(LoginStatus Status, AppUser? User = null, TokenPair? Tokens = null);

public sealed class AuthService(
    BmaDbContext db,
    IOptions<JwtOptions> options,
    AuditWriter audit)
{
    private readonly JwtOptions jwt = options.Value;
    private readonly PasswordHasher<AppUser> hasher = new();

    public async Task<(bool Created, AppUser? User)> RegisterAsync(
        string username,
        string password,
        string displayName,
        string? employeeCode,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(username) || string.IsNullOrWhiteSpace(password) ||
            string.IsNullOrWhiteSpace(displayName))
            return (false, null);
        var normalized = Normalize(username);
        var employee = NullIfWhiteSpace(employeeCode);
        if (normalized.Length is < 3 or > 64 || password.Length is < 10 or > 200 ||
            displayName.Trim().Length > 120 || employee?.Length > 64)
            return (false, null);
        if (await db.AppUsers.AnyAsync(x => x.NormalizedUserName == normalized ||
            employee != null && x.EmployeeCode == employee, ct))
            return (false, null);

        var user = new AppUser
        {
            UserName = username.Trim(),
            NormalizedUserName = normalized,
            DisplayName = displayName.Trim(),
            EmployeeCode = employee,
            PasswordHash = ""
        };
        user.PasswordHash = hasher.HashPassword(user, password);
        db.AppUsers.Add(user);
        audit.Add("ACCOUNT_REGISTERED", "USER", user.Id.ToString(), user.Id,
            after: new { user.UserName, user.DisplayName, user.EmployeeCode, user.Status });
        try
        {
            await db.SaveChangesAsync(ct);
            return (true, user);
        }
        catch (DbUpdateException)
        {
            // A concurrent registration can win either unique index after the
            // pre-check. Return the same conflict response instead of HTTP 500.
            return (false, null);
        }
    }

    public async Task<LoginOutcome> LoginAsync(
        string username,
        string password,
        string? deviceName,
        string? ipAddress,
        CancellationToken ct)
    {
        var user = await FindAndVerifyAsync(username, password, ct);
        if (user is null) return new(LoginStatus.InvalidCredentials);

        var status = user.Status switch
        {
            AccountStatus.Pending => LoginStatus.Pending,
            AccountStatus.Rejected => LoginStatus.Rejected,
            AccountStatus.Disabled => LoginStatus.Disabled,
            _ => LoginStatus.Success
        };
        if (status != LoginStatus.Success) return new(status, user);

        var tokens = CreateTokenPair(user, deviceName, ipAddress, Guid.NewGuid().ToString("N"));
        audit.Add("LOGIN_SUCCEEDED", "USER", user.Id.ToString(), user.Id);
        await db.SaveChangesAsync(ct);
        return new(LoginStatus.Success, user, tokens);
    }

    public async Task<AppUser?> VerifyAdminAsync(string username, string password, CancellationToken ct)
    {
        var user = await FindAndVerifyAsync(username, password, ct);
        return user is { Status: AccountStatus.Approved } && HasRole(user, "Admin") ? user : null;
    }

    public async Task<TokenPair?> RefreshAsync(
        string rawToken,
        string? deviceName,
        string? ipAddress,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(rawToken)) return null;
        var hash = Hash(rawToken);
        await using var transaction = await db.Database.BeginTransactionAsync(ct);
        // Serialize rotation for one refresh token. Without a row lock, two
        // simultaneous requests can both mint a valid successor before either
        // request marks the original token as rotated.
        var session = await db.RefreshSessions
            .FromSqlInterpolated($"SELECT * FROM refresh_sessions WHERE token_hash = {hash} FOR UPDATE")
            .SingleOrDefaultAsync(ct);
        if (session is null) return null;
        session.User = await db.AppUsers.SingleOrDefaultAsync(x => x.Id == session.UserId, ct);
        if (session.User is null) return null;

        if (session.RevokedAt is not null)
        {
            if (session.ReplacedByHash is not null)
            {
                await RevokeFamilyAsync(session.TokenFamily, "REFRESH_TOKEN_REUSE", ct);
                await transaction.CommitAsync(ct);
            }
            return null;
        }

        if (session.ExpiresAt <= DateTimeOffset.UtcNow || session.User.Status != AccountStatus.Approved)
        {
            session.RevokedAt = DateTimeOffset.UtcNow;
            session.RevocationReason = "EXPIRED_OR_USER_DISABLED";
            await db.SaveChangesAsync(ct);
            await transaction.CommitAsync(ct);
            return null;
        }

        var tokens = CreateTokenPair(session.User, deviceName ?? session.DeviceName,
            ipAddress ?? session.IpAddress, session.TokenFamily);
        session.RevokedAt = DateTimeOffset.UtcNow;
        session.RevocationReason = "ROTATED";
        session.ReplacedByHash = Hash(tokens.RefreshToken);
        audit.Add("REFRESH_ROTATED", "SESSION", session.Id.ToString(), session.UserId);
        await db.SaveChangesAsync(ct);
        await transaction.CommitAsync(ct);
        return tokens;
    }

    public async Task RevokeAsync(Guid userId, string rawToken, string reason, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(rawToken)) return;
        var hash = Hash(rawToken);
        var session = await db.RefreshSessions.SingleOrDefaultAsync(
            x => x.UserId == userId && x.TokenHash == hash, ct);
        if (session is null || session.RevokedAt is not null) return;
        session.RevokedAt = DateTimeOffset.UtcNow;
        session.RevocationReason = reason;
        audit.Add("SESSION_REVOKED", "SESSION", session.Id.ToString(), userId,
            after: new { reason });
        await db.SaveChangesAsync(ct);
    }

    public async Task<bool> SetApprovalAsync(Guid targetId, Guid actorId, bool approved, CancellationToken ct)
    {
        var user = await db.AppUsers.SingleOrDefaultAsync(x => x.Id == targetId, ct);
        if (user is null) return false;

        EmployeeProfile? profile = null;
        if (approved && !string.IsNullOrWhiteSpace(user.EmployeeCode))
        {
            profile = await db.EmployeeProfiles.SingleOrDefaultAsync(
                x => x.EmployeeCode == user.EmployeeCode, ct);
            if (profile is null || profile.UserId is not null && profile.UserId != user.Id)
                return false;
            var otherProfile = await db.EmployeeProfiles.AsNoTracking().AnyAsync(
                x => x.UserId == user.Id && x.Id != profile.Id, ct);
            if (otherProfile) return false;
            profile.UserId = user.Id;
            profile.UpdatedAt = DateTimeOffset.UtcNow;
        }

        var before = user.Status;
        user.Status = approved ? AccountStatus.Approved : AccountStatus.Rejected;
        user.ApprovedAt = approved ? DateTimeOffset.UtcNow : null;
        user.ApprovedBy = actorId;
        if (profile is not null)
            audit.Add("ACCOUNT_EMPLOYEE_LINKED", "EMPLOYEE_PROFILE", profile.Id.ToString(), actorId,
                after: new { profile.EmployeeCode, UserId = user.Id });
        audit.Add(approved ? "ACCOUNT_APPROVED" : "ACCOUNT_REJECTED", "USER",
            user.Id.ToString(), actorId, new { Status = before }, new { user.Status });
        await db.SaveChangesAsync(ct);
        return true;
    }

    private async Task<AppUser?> FindAndVerifyAsync(string username, string password, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(username) || string.IsNullOrWhiteSpace(password)) return null;
        var user = await db.AppUsers.SingleOrDefaultAsync(
            x => x.NormalizedUserName == Normalize(username), ct);
        if (user is null) return null;
        var result = hasher.VerifyHashedPassword(user, user.PasswordHash, password);
        if (result == PasswordVerificationResult.Failed) return null;
        if (result == PasswordVerificationResult.SuccessRehashNeeded)
        {
            user.PasswordHash = hasher.HashPassword(user, password);
            await db.SaveChangesAsync(ct);
        }
        return user;
    }

    private TokenPair CreateTokenPair(AppUser user, string? deviceName, string? ipAddress, string family)
    {
        var now = DateTimeOffset.UtcNow;
        var accessExpiry = now.AddMinutes(Math.Clamp(jwt.AccessMinutes, 5, 60));
        var refreshExpiry = now.AddDays(Math.Clamp(jwt.RefreshDays, 7, 365));
        var claims = new List<Claim>
        {
            new(JwtRegisteredClaimNames.Sub, user.Id.ToString()),
            new(JwtRegisteredClaimNames.UniqueName, user.UserName),
            new("display_name", user.DisplayName)
        };
        foreach (var role in Roles(user)) claims.Add(new("role", role));

        var credentials = new SigningCredentials(
            new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwt.SigningKey)),
            SecurityAlgorithms.HmacSha256);
        var token = new JwtSecurityToken(jwt.Issuer, jwt.Audience, claims,
            notBefore: now.UtcDateTime, expires: accessExpiry.UtcDateTime,
            signingCredentials: credentials);
        var rawRefresh = Convert.ToBase64String(RandomNumberGenerator.GetBytes(64));
        db.RefreshSessions.Add(new RefreshSession
        {
            UserId = user.Id,
            TokenHash = Hash(rawRefresh),
            TokenFamily = family,
            DeviceName = NullIfWhiteSpace(deviceName),
            IpAddress = NullIfWhiteSpace(ipAddress),
            ExpiresAt = refreshExpiry
        });
        return new(new JwtSecurityTokenHandler().WriteToken(token), rawRefresh, accessExpiry, refreshExpiry);
    }

    private async Task RevokeFamilyAsync(string family, string reason, CancellationToken ct)
    {
        var now = DateTimeOffset.UtcNow;
        var sessions = await db.RefreshSessions
            .Where(x => x.TokenFamily == family && x.RevokedAt == null).ToListAsync(ct);
        foreach (var item in sessions)
        {
            item.RevokedAt = now;
            item.RevocationReason = reason;
        }
        audit.Add("TOKEN_FAMILY_REVOKED", "TOKEN_FAMILY", family, after: new { reason });
        await db.SaveChangesAsync(ct);
    }

    public static string[] Roles(AppUser user) => user.Roles.Split(',',
        StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
    public static bool HasRole(AppUser user, string role) =>
        Roles(user).Contains(role, StringComparer.OrdinalIgnoreCase);
    public static string Hash(string value) => Convert.ToHexString(
        SHA256.HashData(Encoding.UTF8.GetBytes(value))).ToLowerInvariant();
    private static string Normalize(string value) => value.Trim().ToUpperInvariant();
    private static string? NullIfWhiteSpace(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
