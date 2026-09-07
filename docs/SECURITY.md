# Security Baseline

## Session

- Access token: 15 phút.
- Refresh session mặc định: 180 ngày để tránh auto-exit không cần thiết.
- Refresh token là random opaque value; DB chỉ lưu SHA-256 hash.
- Mỗi refresh rotate token. Replay/reuse token cũ revoke toàn token family.
- Rotation khóa hàng PostgreSQL của token gốc, nên hai request refresh đồng thời
  không thể cùng phát hành hai successor hợp lệ.
- Admin có thể revoke user/device khi nghi xâm nhập.
- Cache đọc offline dùng namespace riêng và bị xóa khi đăng nhập tài khoản khác,
  đăng xuất hoặc refresh token bị thu hồi; không để hồ sơ/chấm công của người
  trước xuất hiện trên điện thoại dùng chung.
- Logout chỉ xóa ba khóa phiên trong secure storage, không dùng `deleteAll` để
  tránh xóa nhầm khóa push/signing được bổ sung về sau.

## Account lifecycle

`PENDING → APPROVED → DISABLED|REJECTED`. Chỉ `APPROVED` được đăng nhập.
Bootstrap Admin chỉ chạy khi hai biến môi trường được cấp, và được audit.

Admin cookie dùng tiền tố `__Secure-` và đúng `PathBase` ở staging/production;
Development dùng tên không tiền tố để kiểm thử qua HTTP local. Không dùng
`__Host-` vì tiền tố đó bắt buộc `Path=/`, trái với việc cô lập BMA dưới
`/bmapp`. Khóa Data Protection được giữ trong volume riêng để restart container
không làm hỏng cookie và antiforgery token đang còn hiệu lực.

## Integration

- Gateway key so sánh constant-time.
- Auth/Admin login và integration ingest có rate-limit riêng; Cloudflare vẫn là
  lớp chống DDoS bên ngoài, rate limiter trong app không thay thế WAF.
- Idempotency unique theo `source_system + event_id`.
- Payload hash được kiểm tra trước commit.
- Signature là optional ở Alpha nhưng bắt buộc với Entry/Exit production nếu
  thiết bị hỗ trợ.
- Raw event/audit không có endpoint update/delete.

## Dữ liệu nhân sự

- Nhân viên chỉ xem hồ sơ/chấm công của mình.
- HR/Admin mới xem/phê duyệt phạm vi được cấp.
- Không dùng analytics quảng cáo, location, contact list hoặc device movement.
- Log không chứa password, token, station key hoặc full evidence image.

## Reverse proxy

- Cloudflare cung cấp `X-Forwarded-Proto`; BMA xử lý header này để tạo redirect
  HTTPS chính xác.
- Vì forwarded headers chỉ an toàn từ proxy tin cậy, cổng container được publish
  duy nhất trên `127.0.0.1`; không được mở trực tiếp ra LAN/Internet.
- `AllowedHosts` giới hạn Host header; CSP, frame denial và Permissions Policy
  giảm bề mặt tấn công của Admin web.
