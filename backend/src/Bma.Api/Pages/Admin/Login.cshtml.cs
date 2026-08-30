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
        ? RedirectToPage("/Admin/Index") : Page();

    public async Task<IActionResult> OnPostAsync(CancellationToken ct)
    {
        if (!ModelState.IsValid) return Page();
        var user = await auth.VerifyAdminAsync(Input.Username, Input.Password, ct);
        if (user is null)
        {
            ModelState.AddModelError(string.Empty, "Tài khoản hoặc quyền quản trị không hợp lệ.");
            return Page();
        }
        var claims = new List<Claim>
        {
            new(ClaimTypes.NameIdentifier, user.Id.ToString()),
            new(ClaimTypes.Name, user.UserName),
            new("display_name", user.DisplayName)
        };
        claims.AddRange(AuthService.Roles(user).Select(x => new Claim(ClaimTypes.Role, x)));
        await HttpContext.SignInAsync(BmaAuthSchemes.Cookie,
            new ClaimsPrincipal(new ClaimsIdentity(claims, BmaAuthSchemes.Cookie)),
            new AuthenticationProperties { IsPersistent = true, AllowRefresh = true });
        return IsLocal(ReturnUrl) ? LocalRedirect(ReturnUrl!) : RedirectToPage("/Admin/Index");
    }

    private static bool IsLocal(string? value) => value is not null && value.StartsWith('/') &&
                                                   !value.StartsWith("//");

    public sealed class LoginInput
    {
        [Required, StringLength(64)] public string Username { get; set; } = "";
        [Required, StringLength(200)] public string Password { get; set; } = "";
    }
}
