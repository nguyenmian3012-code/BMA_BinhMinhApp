using System.Security.Claims;
using Bma.Data;
using Bma.Domain;
using Bma.Modules;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.EntityFrameworkCore;

namespace Bma.Pages.Admin.Employees;

[Authorize(Policy = "PeopleEditor")]
public sealed class IndexModel(BmaDbContext db, AuditWriter audit) : PageModel
{
    public List<EmployeeProfile> Items { get; private set; } = [];

    [TempData] public string? Notice { get; set; }
    [TempData] public string? ErrorMessage { get; set; }

    public async Task OnGetAsync(CancellationToken ct) => Items = await db.EmployeeProfiles
        .AsNoTracking().OrderBy(x => x.EmployeeCode).Take(500).ToListAsync(ct);

    public async Task<IActionResult> OnPostCreateAsync(
        string code, string fullName, string? department, string? position, DateOnly? hiredOn,
        CancellationToken ct)
    {
        code = (code ?? "").Trim().ToUpperInvariant();
        fullName = (fullName ?? "").Trim();
        department = Clean(department);
        position = Clean(position);
        if (!EmployeeCodeRules.IsValid(code) ||
            fullName.Length is < 2 or > 120 || department?.Length > 120 || position?.Length > 120)
            return Fail("Mã cần dạng BM001. Họ tên và thông tin phải hợp lệ.");
        if (await db.EmployeeProfiles.AnyAsync(x => x.EmployeeCode.ToUpper() == code, ct))
            return Fail("Mã đã có trong hồ sơ. Kiểm tra trước khi tạo.");
        if (await db.EmployeeProfiles.AnyAsync(x => x.FullName.ToUpper() == fullName.ToUpperInvariant(), ct))
            return Fail("Đã có người trùng họ tên. Xác minh nhân sự trước khi tạo mã mới.");

        var profile = new EmployeeProfile
        {
            EmployeeCode = code,
            FullName = fullName,
            Department = department,
            Position = position,
            HiredOn = hiredOn,
            EffectiveFrom = DateOnly.FromDateTime(DateTime.UtcNow)
        };
        db.EmployeeProfiles.Add(profile);
        audit.Add("EMPLOYEE_CREATED", "EMPLOYEE_PROFILE", profile.Id.ToString(), Actor(),
            after: new { profile.EmployeeCode, profile.FullName, profile.Department, profile.Position, profile.HiredOn });
        try { await db.SaveChangesAsync(ct); }
        catch (DbUpdateException) { return Fail("Trùng mã hoặc dữ liệu không hợp lệ. Chưa lưu."); }
        Notice = $"Đã thêm {code}.";
        return RedirectToPage();
    }

    public async Task<IActionResult> OnPostUpdateAsync(Guid id, string? department, string? position,
        DateOnly? hiredOn, bool isActive, CancellationToken ct)
    {
        department = Clean(department);
        position = Clean(position);
        if (department?.Length > 120 || position?.Length > 120)
            return Fail("Bộ phận hoặc chức vụ quá dài.");
        var profile = await db.EmployeeProfiles.SingleOrDefaultAsync(x => x.Id == id, ct);
        if (profile is null) return NotFound();
        var before = new { profile.Department, profile.Position, profile.HiredOn, profile.IsActive };
        profile.Department = department;
        profile.Position = position;
        profile.HiredOn = hiredOn;
        profile.IsActive = isActive;
        if (!isActive && profile.UserId is Guid userId)
        {
            var sessions = await db.RefreshSessions
                .Where(x => x.UserId == userId && x.RevokedAt == null).ToListAsync(ct);
            foreach (var session in sessions)
            {
                session.RevokedAt = DateTimeOffset.UtcNow;
                session.RevocationReason = "EMPLOYEE_INACTIVE";
            }
        }
        profile.Version++;
        profile.UpdatedAt = DateTimeOffset.UtcNow;
        audit.Add("EMPLOYEE_UPDATED", "EMPLOYEE_PROFILE", profile.Id.ToString(), Actor(),
            before, new { profile.Department, profile.Position, profile.HiredOn, profile.IsActive });
        await db.SaveChangesAsync(ct);
        Notice = $"Đã cập nhật {profile.EmployeeCode}.";
        return RedirectToPage();
    }

    private IActionResult Fail(string message)
    {
        ErrorMessage = message;
        return RedirectToPage();
    }

    private Guid Actor() => Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
    private static string? Clean(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
