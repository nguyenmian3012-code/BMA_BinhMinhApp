# Security Baseline

## Session

- Access token: 15 phút.
- Refresh session mặc định: 180 ngày để tránh auto-exit không cần thiết.
- Refresh token là random opaque value; DB chỉ lưu SHA-256 hash.
- Mỗi refresh rotate token. Replay/reuse token cũ revoke toàn token family.
- Admin có thể revoke user/device khi nghi xâm nhập.

## Account lifecycle

`PENDING → APPROVED → DISABLED|REJECTED`. Chỉ `APPROVED` được đăng nhập.
Bootstrap Admin chỉ chạy khi hai biến môi trường được cấp, và được audit.

## Integration

- Gateway key so sánh constant-time.
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
