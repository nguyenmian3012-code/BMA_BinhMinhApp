# Các bước Anh cần thao tác thủ công

## Blocker gần nhất

1. Trên máy MinhComp, xác nhận thư mục/source thật đang chạy Gateway/ABMT Core.
2. Không gửi key; chỉ gửi đường dẫn repo/file và output lệnh không chứa secret.
3. Xác nhận `com.binhminh.bma` và port local `8790`.
4. Chọn một Samsung Fold 7 hoặc S24 Ultra làm Android pilot.

## Trước staging

- Tạo database/user PostgreSQL staging và đặt secret trực tiếp trên host.
- Cấp route `/bmapp-staging/*` trong Cloudflare Tunnel.
- Đặt `Gateway__InboundKey` giống nhau ở Gateway và BMA staging.
- Chạy health check và gửi lại status code/body đã che thông tin nhạy cảm.

## Trước Android Alpha

- Bật Developer options và USB debugging.
- Cắm cáp, chấp nhận fingerprint máy phát triển.
- Cài APK từ GitHub Actions artifact và test login/session/notification UI.

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
