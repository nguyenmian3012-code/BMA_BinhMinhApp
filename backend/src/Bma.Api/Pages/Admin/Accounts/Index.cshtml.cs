using System.Security.Claims;
using Bma.Authentication;
using Bma.Data;
using Bma.Domain;
using Bma.Modules;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.EntityFrameworkCore;

namespace Bma.Pages.Admin.Accounts;

[Authorize(Policy = "Admin")]
public sealed class IndexModel(BmaDbContext db, AuthService auth, AuditWriter audit) : PageModel
{
    public List<AppUser> Items { get; private set; } = [];
    public List<AppUser> ActiveAccounts { get; private set; } = [];

    [TempData]
    public string? ErrorMessage { get; set; }

    public async Task OnGetAsync(CancellationToken ct)
    {
        Items = await db.AppUsers.AsNoTracking()
            .Where(x => x.Status == AccountStatus.Pending).OrderBy(x => x.CreatedAt).ToListAsync(ct);
        ActiveAccounts = await db.AppUsers.AsNoTracking()
            .Where(x => x.Status == AccountStatus.Approved).OrderBy(x => x.UserName).Take(500).ToListAsync(ct);
    }

    public async Task<IActionResult> OnPostApproveAsync(Guid id, CancellationToken ct)
    {
        if (!await auth.SetApprovalAsync(id, ActorId(), true, ct))
            ErrorMessage = "Không thể duyệt: mã nhân viên chưa có hồ sơ hoặc đã liên kết tài khoản khác.";
        return RedirectToPage();
    }

    public async Task<IActionResult> OnPostRejectAsync(Guid id, CancellationToken ct)
    {
        await auth.SetApprovalAsync(id, ActorId(), false, ct);
        return RedirectToPage();
    }

    public async Task<IActionResult> OnPostRoleAsync(Guid id, string role, CancellationToken ct)
    {
        var allowed = new[] { "Employee", "Accounting", "Operations", "Executive", "HR" };
        var account = await db.AppUsers.SingleOrDefaultAsync(x => x.Id == id, ct);
        if (account is not { Status: AccountStatus.Approved } ||
            AuthService.HasRole(account, "Admin") || !allowed.Contains(role, StringComparer.Ordinal))
        {
            ErrorMessage = "Không thể đổi quyền cho tài khoản này.";
            return RedirectToPage();
        }
        var previous = account.Roles;
        account.Roles = role;
        account.AuthVersion++;
        var sessions = await db.RefreshSessions
            .Where(x => x.UserId == id && x.RevokedAt == null).ToListAsync(ct);
        foreach (var session in sessions)
        {
            session.RevokedAt = DateTimeOffset.UtcNow;
            session.RevocationReason = "ROLE_CHANGED";
        }
        audit.Add("ACCOUNT_ROLE_CHANGED", "USER", id.ToString(), ActorId(),
            before: new { Roles = previous }, after: new { account.Roles });
        await db.SaveChangesAsync(ct);
        return RedirectToPage();
    }

    private Guid ActorId() => Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
}
