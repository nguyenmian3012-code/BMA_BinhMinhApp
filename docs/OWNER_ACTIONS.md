# Các bước Minh An cần thực hiện

## Blocker hiện tại

Chạy trên MinhComp bằng PowerShell **Run as administrator**:

```powershell
Set-Location C:\ABMT\BMA_BinhMinhApp-v032

git status --short --branch
git pull --ff-only

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\infra\scripts\restore-staging-origin.ps1
```

Nhập mật khẩu PostgreSQL `postgres` khi script hỏi. Không gửi mật khẩu vào chat.
Docker Desktop không cần chạy.

Kết quả bắt buộc:

```text
Native PostgreSQL: PASS
Windows Service: PASS
Local health: PASS
Runtime: windows-service
Database: postgresql-native
EmployeeScan: True
```

Nếu thiếu .NET 10 SDK, tải artifact `bma-native-win-x64` của commit mới nhất.
Sau đó chạy:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\infra\scripts\restore-staging-origin.ps1 `
  -PackagePath "$env:USERPROFILE\Downloads\bma-native-win-x64.zip"
```

## Sau public health

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\infra\scripts\staging-integration-check.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\Deploy-BMA-Terminal-v0.3.2.ps1
```

Gửi output PASS. Không gửi `.env.staging`.

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
