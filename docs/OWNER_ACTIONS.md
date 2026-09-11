# Các bước Anh cần thao tác thủ công

## Blocker gần nhất

1. Trên máy MinhComp, khôi phục origin staging `8791` bằng script bên dưới.
2. Xác nhận thư mục/source thật đang chạy Gateway/ABMT Core và ABMT Remote.
3. Không gửi key; chỉ gửi đường dẫn repo/file và output lệnh không chứa secret.
4. Xác nhận `com.binhminh.bma` và port local `8790`.
5. Chọn một Samsung Fold 7 hoặc S24 Ultra làm Android pilot.

## Trước staging

- Tạo database/user PostgreSQL staging và đặt secret trực tiếp trên host.
- Cấp route regex `^/bmapp-staging(/.*)?$` trong Cloudflare Tunnel, đặt trước
  route catch-all của `gateway.abmtlab.com`; Cloudflare giữ nguyên path khi
  chuyển tiếp đến `http://localhost:8791`.
- Trong `.env.staging`, đặt `BMA_HOST_PORT=8791` và
  `BMA_PATH_BASE=/bmapp-staging`; production giữ `BMA_HOST_PORT=8790` và
  `BMA_PATH_BASE=/bmapp`.
- Khởi động với `--project-name bma-staging`; không dùng cùng Compose project
  với production và không chạy `docker compose down -v`.
- Đặt `Gateway__InboundKey` giống nhau ở Gateway và BMA staging.
- Chạy `infra/scripts/health-check.ps1 -BaseUrl http://localhost:8791
  -PathBase /bmapp-staging` và gửi lại output không chứa secret.

Khôi phục và kiểm tra local/public bằng một lệnh an toàn:

```powershell
Set-Location C:\ABMT\BMA_BinhMinhApp
git switch codex/terminal-bridge-v0-3
git pull --ff-only
powershell.exe -ExecutionPolicy Bypass -File .\infra\scripts\restore-staging-origin.ps1
```

Script dừng nếu project không phải `bma-staging`, port không phải `8791`, hoặc
path không phải `/bmapp-staging`. Script không xóa volume.

Khi public health PASS, chạy synthetic ingest gồm MotorNode và BMKCS:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\infra\scripts\staging-integration-check.ps1
```

## Trước Android Alpha

- Bật Developer options và USB debugging trên một Samsung Fold 7 hoặc S24 Ultra.
- Cắm đúng một thiết bị, chấp nhận fingerprint máy phát triển và giữ màn hình mở.
- Chỉ dùng artifact `bma-android-alpha-staging` từ CI xanh của đúng commit cần
  test. Artifact phải chứa APK arm64, `BUILD_INFO.txt` và `SHA256SUMS.txt`.
- Chạy `infra/scripts/install-android-alpha.ps1` với đường dẫn ZIP; script tự
  kiểm checksum, ADB install, package ID và launch.
- Thực hiện `docs/ANDROID_ALPHA_TEST.md`: login, giữ session, năm trang chính,
  offline cache, inbox và logout.
- APK profile từ CI dùng khóa ký tạm thời, chỉ dành cho physical-device Alpha.
  Kênh pilot bền vững cần khóa Android nội bộ ổn định lưu ngoài Git/chat.

## Trước ABMT Remote v1.1

- Tìm source WinForms v1.0 bằng lệnh trong
  [`ABMT_REMOTE_V1_1_PLAN.md`](ABMT_REMOTE_V1_1_PLAN.md).
- Chỉ gửi path/source hoặc repository; không gửi `.env` và key.
- Giữ ABMT và Bình Minh thành hai nhóm điều khiển độc lập.

## Trước iOS/TestFlight

- Chuẩn bị Mac/Xcode hoặc macOS CI, Apple Developer và App Store Connect.
- Tạo APNs key trong tài khoản Bình Minh; không gửi key qua chat.
- Có ít nhất một iPhone thật để test.

## Block Production

- Source/contract thật của Entry/Exit.
- Công thức lương, tăng ca, nghỉ phép, grace và adjustment.
- Privacy policy, account deletion/revocation và support contact.
- Công thức recovery + nguồn cân đầu vào/đầu ra cùng basis.
- Apple/Google verification và danh sách pilot được duyệt.
