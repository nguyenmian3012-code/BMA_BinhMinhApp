using Bma.Authentication;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace Bma.Pages.Admin;

[Authorize]
public sealed class LogoutModel : PageModel
{
    public IActionResult OnGet() => Redirect("/bmapp/admin");

    public async Task<IActionResult> OnPostAsync()
    {
        await HttpContext.SignOutAsync(BmaAuthSchemes.Cookie);
        return Redirect("/bmapp/admin/login");
    }
}
