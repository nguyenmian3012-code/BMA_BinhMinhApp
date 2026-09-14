using System.Security.Claims;
using Bma.Authentication;
using Bma.Data;
using Bma.Domain;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.EntityFrameworkCore;

namespace Bma.Pages.Admin.Accounts;

[Authorize(Policy = "Admin")]
public sealed class IndexModel(BmaDbContext db, AuthService auth) : PageModel
{
    public List<AppUser> Items { get; private set; } = [];

    public async Task OnGetAsync(CancellationToken ct) => Items = await db.AppUsers.AsNoTracking()
        .Where(x => x.Status == AccountStatus.Pending).OrderBy(x => x.CreatedAt).ToListAsync(ct);

    public async Task<IActionResult> OnPostApproveAsync(Guid id, CancellationToken ct)
    {
        await auth.SetApprovalAsync(id, ActorId(), true, ct);
        return RedirectToPage();
    }

    public async Task<IActionResult> OnPostRejectAsync(Guid id, CancellationToken ct)
    {
        await auth.SetApprovalAsync(id, ActorId(), false, ct);
        return RedirectToPage();
    }

    private Guid ActorId() => Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
}
