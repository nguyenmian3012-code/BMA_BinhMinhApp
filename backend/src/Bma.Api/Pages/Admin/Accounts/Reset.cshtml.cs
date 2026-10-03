using System.Security.Claims;
using System.Security.Cryptography;
using Bma.Data;
using Bma.Domain;
using Bma.Modules;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.EntityFrameworkCore;

namespace Bma.Pages.Admin.Accounts;

[Authorize(Policy = "Admin")]
public sealed class ResetModel(BmaDbContext db, AuditWriter audit) : PageModel
{
    public string? ErrorMessage { get; private set; }
    public string? TemporaryPassword { get; private set; }
    public string? ResetUserName { get; private set; }

    public void OnGet() => Response.Headers["Cache-Control"] = "no-store";

    public async Task<IActionResult> OnPostAsync(string username, CancellationToken ct)
    {
        Response.Headers["Cache-Control"] = "no-store";
        var normalized = (username ?? "").Trim().ToUpperInvariant();
        if (normalized.Length is < 3 or > 64)
        {
            ErrorMessage = "Nhập tên đăng nhập hợp lệ.";
            return Page();
        }
        var account = await db.AppUsers.SingleOrDefaultAsync(x => x.NormalizedUserName == normalized, ct);
        if (account is not { Status: AccountStatus.Approved })
        {
            ErrorMessage = "Không tìm thấy tài khoản đã duyệt.";
            return Page();
        }
        var actor = Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
        if (account.Id == actor)
        {
            ErrorMessage = "Đổi mật khẩu của chính mình trong ứng dụng.";
            return Page();
        }

        var newPassword = Convert.ToHexString(RandomNumberGenerator.GetBytes(12));
        account.PasswordHash = new PasswordHasher<AppUser>().HashPassword(account, newPassword);
        account.AuthVersion++;
        var sessions = await db.RefreshSessions
            .Where(x => x.UserId == account.Id && x.RevokedAt == null).ToListAsync(ct);
        foreach (var session in sessions)
        {
            session.RevokedAt = DateTimeOffset.UtcNow;
            session.RevocationReason = "ADMIN_PASSWORD_RESET";
        }
        audit.Add("PASSWORD_RESET_BY_ADMIN", "USER", account.Id.ToString(), actor);
        await db.SaveChangesAsync(ct);
        TemporaryPassword = newPassword;
        ResetUserName = account.UserName;
        return Page();
    }
}
