using System.ComponentModel.DataAnnotations;
using System.Security.Claims;
using Bma.Authentication;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.AspNetCore.RateLimiting;

namespace Bma.Pages.Admin;

[AllowAnonymous]
[EnableRateLimiting("auth")]
public sealed class LoginModel(AuthService auth) : PageModel
{
    [BindProperty] public LoginInput Input { get; set; } = new();
    [BindProperty(SupportsGet = true)] public string? ReturnUrl { get; set; }

    public IActionResult OnGet() => User.Identity?.IsAuthenticated == true
        ? RedirectToPage(User.IsInRole("Admin") ? "/Admin/Index" : "/Admin/Employees/Index") : Page();

    public async Task<IActionResult> OnPostAsync(CancellationToken ct)
    {
        if (!ModelState.IsValid) return Page();
        var user = await auth.VerifyPeopleEditorAsync(Input.Username, Input.Password, ct);
        if (user is null)
        {
            ModelState.AddModelError(string.Empty, "Tài khoản hoặc quyền quản lý nhân sự không hợp lệ.");
            return Page();
        }
        var claims = new List<Claim>
        {
            new(ClaimTypes.NameIdentifier, user.Id.ToString()),
            new(ClaimTypes.Name, user.UserName),
            new("display_name", user.DisplayName),
            new("auth_version", user.AuthVersion.ToString(System.Globalization.CultureInfo.InvariantCulture))
        };
        claims.AddRange(AuthService.Roles(user).Select(x => new Claim(ClaimTypes.Role, x)));
        await HttpContext.SignInAsync(BmaAuthSchemes.Cookie,
            new ClaimsPrincipal(new ClaimsIdentity(claims, BmaAuthSchemes.Cookie)),
            new AuthenticationProperties { IsPersistent = true, AllowRefresh = true });
        return Url.IsLocalUrl(ReturnUrl) ? LocalRedirect(ReturnUrl!) :
            RedirectToPage(AuthService.HasRole(user, "Admin") ? "/Admin/Index" : "/Admin/Employees/Index");
    }

    public sealed class LoginInput
    {
        [Required, StringLength(64)] public string Username { get; set; } = "";
        [Required, StringLength(200)] public string Password { get; set; } = "";
    }
}
