# Deployment Windows native

## Kiến trúc đã khóa

| Môi trường | Windows Service | URL local | PostgreSQL native |
| --- | --- | --- | --- |
| Staging | `BMA-Staging` | `127.0.0.1:8791/bmapp-staging` | `binhminh_data_staging` |
| Production | `BMA-Production` | `127.0.0.1:8790/bmapp` | `binhminh_data` |

MinhComp không cần Docker Desktop. BMA Core chạy bằng Windows Service. Cả hai
database nằm trong PostgreSQL 17 Windows. Staging không được kết nối
`binhminh_data`.

Cloudflare Tunnel giữ nguyên path. Cổng chỉ bind `127.0.0.1`; không mở BMA trực
tiếp ra LAN hoặc Internet. Data Protection keys nằm ngoài release directory,
được giữ qua mỗi lần nâng cấp.

## Chuẩn bị staging

```powershell
Copy-Item .env.example .env.staging
notepad .env.staging
```

Thay toàn bộ `CHANGE_ME`. Các giá trị bắt buộc:

```text
BMA_DB_NAME=binhminh_data_staging
BMA_DB_USER=bma_staging_runtime
BMA_PATH_BASE=/bmapp-staging
BMA_HOST_PORT=8791
```

Không ghi mật khẩu PostgreSQL `postgres` vào file. Script chỉ hỏi mật khẩu này
khi cần tạo database/user staging lần đầu.

## Deploy staging

Mở PowerShell bằng **Run as administrator**:

```powershell
Set-Location C:\ABMT\BMA_BinhMinhApp-v032

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\infra\scripts\restore-staging-origin.ps1
```

Nếu máy không có .NET 10 SDK, tải artifact `bma-native-win-x64` của đúng commit:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\infra\scripts\restore-staging-origin.ps1 `
  -PackagePath C:\Users\Mian\Downloads\bma-native-win-x64.zip
```

Script thực hiện:

1. Kiểm tra PostgreSQL 17 native.
2. Tạo database staging riêng.
3. Publish hoặc giải nén BMA.
4. Cài `BMA-Staging` tự khởi động.
5. Giới hạn quyền thư mục secret.
6. Kiểm tra local và public health.

Health hợp lệ phải chứa:

```json
{
  "ok": true,
  "runtime": "windows-service",
  "database": "postgresql-native"
}
```

## Synthetic integration

Chỉ chạy với database staging:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\infra\scripts\staging-integration-check.ps1
```

Script dừng nếu database mang tên `binhminh_data`.

## Backup và restore gate

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\infra\scripts\verify-backup-restore.ps1
```

Backup được restore vào database tạm có prefix `bma_restore_check_`. Database
tạm bị xóa sau kiểm tra. Database nguồn không bị thay đổi.

## Production

Production chỉ chuyển sang `BMA-Production` sau khi staging, Bridge,
`EMPLOYEE_SCAN`, Profile, Attendance và BMKCS đều PASS. Script không tự tạo hoặc
thay đổi database production.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\infra\scripts\deploy-native-bma-service.ps1 `
  -Target Production `
  -EnvFile .env.production `
  -PackagePath C:\Path\bma-native-win-x64.zip
```

Trước lệnh trên: backup `binhminh_data`; xác nhận port `8790` trống; xác nhận
Cloudflare `/bmapp` trỏ `http://localhost:8790`.

## Rollback

Mỗi deploy tạo release mới dưới:

```text
C:\ABMT\BMA-Services\BMA-Staging\releases
C:\ABMT\BMA-Services\BMA-Production\releases
```

Nếu health mới thất bại, script tự trả service về binary trước. Migration chỉ
được phép additive. Không downgrade database tự động.

## Secrets

`appsettings.Production.json` được tạo trên MinhComp. ACL chỉ cấp quyền cho
SYSTEM, Administrators và service tương ứng. Không commit, chụp màn hình hoặc
gửi nội dung file này.
