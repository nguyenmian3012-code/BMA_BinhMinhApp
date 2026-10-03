# Các bước Minh An cần thực hiện

## Blocker hiện tại (13/09/2026)

Staging PostgreSQL native đã PASS. Lần chạy `1e0df64` dừng tại `sc.exe
config BMA-Staging`; không coi local/public health là PASS. Chỉ chạy lại sau
khi CI của commit sửa lệnh `sc.exe` đạt PASS.

Chạy trên MinhComp bằng PowerShell **Run as administrator**:

```powershell
Set-Location C:\ABMT\BMA_BinhMinhApp-v032

git status --short --branch
git fetch origin
git switch --detach origin/codex/windows-native-runtime-v0-3-3

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\Deploy-BMA-Terminal-v0.3.2.ps1 `
  -BmaEnvPath .\.env.staging `
  -PackagePath "$env:USERPROFILE\Downloads\bma-native-win-x64.zip"
```

Nếu role/database staging đã được tạo ở lần trước, mật khẩu `postgres` không
được hỏi lại. Không gửi mật khẩu vào chat. Docker Desktop không cần chạy.

Kết quả bắt buộc:

```text
Native PostgreSQL: PASS
Windows Service: PASS
Local health: PASS
Runtime: windows-service
Database: postgresql-native
EmployeeScan: True
```

Tải artifact `bma-native-win-x64` của đúng CI commit sau khi CI PASS. Nếu
local health PASS nhưng public 502, kiểm tra Cloudflare route 8791 trước khi
restart Bridge.

## Sau public health

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\infra\scripts\staging-integration-check.ps1
```

Script Deploy-BMA-Terminal đã nâng Bridge một lần, không chạy lại. Gửi output
PASS; không gửi `.env.staging`.

## Android Alpha

1. Bật Developer options.
2. Bật USB debugging.
3. Cắm một điện thoại.
4. Chấp nhận fingerprint.
5. Tải artifact `bma-android-alpha-staging`.
6. Chạy `infra/scripts/install-android-alpha.ps1`.
7. Thực hiện `docs/ANDROID_ALPHA_TEST.md`.

## Chưa chuyển production

Giữ `/bmapp` và port `8790` nguyên trạng. Chỉ chuyển `BMA-Production` sau khi:

- Public staging PASS.
- Synthetic BMKCS PASS.
- Synthetic `EMPLOYEE_SCAN` PASS.
- Profile liên kết đúng.
- Attendance mobile hiển thị đúng.
- Backup/restore native PASS.
