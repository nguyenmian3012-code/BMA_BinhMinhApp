# Các bước Anh cần thao tác thủ công

## Blocker gần nhất

1. Trên máy MinhComp, xác nhận thư mục/source thật đang chạy Gateway/ABMT Core.
2. Không gửi key; chỉ gửi đường dẫn repo/file và output lệnh không chứa secret.
3. Xác nhận `com.binhminh.bma` và port local `8790`.
4. Chọn một Samsung Fold 7 hoặc S24 Ultra làm Android pilot.

## Trước staging

- Tạo database/user PostgreSQL staging và đặt secret trực tiếp trên host.
- Cấp route `/bmapp-staging/*` trong Cloudflare Tunnel.
- Trong `.env.staging`, đặt `BMA_HOST_PORT=8791` và
  `BMA_PATH_BASE=/bmapp-staging`; production giữ `BMA_HOST_PORT=8790` và
  `BMA_PATH_BASE=/bmapp`.
- Khởi động với `--project-name bma-staging`; không dùng cùng Compose project
  với production và không chạy `docker compose down -v`.
- Đặt `Gateway__InboundKey` giống nhau ở Gateway và BMA staging.
- Chạy `infra/scripts/health-check.ps1 -BaseUrl http://localhost:8791
  -PathBase /bmapp-staging` và gửi lại output không chứa secret.

## Trước Android Alpha

- Bật Developer options và USB debugging.
- Cắm cáp, chấp nhận fingerprint máy phát triển.
- Nếu quota cho phép, dùng GitHub Actions artifact để test nhanh; đây không phải
  kênh phát hành chính.
- Nếu artifact không có, build APK Alpha đã ký trên máy kiểm soát, ghi SHA-256,
  chép lên MinhComp và tải qua HTTPS `/bmapp/download`.
- Cài APK và test login, giữ session, 5 trang chính và inbox thông báo.

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
