# ADR-0002: Attendance source độc lập

- Status: Accepted
- Date: 2026-08-30

## Decision

Điện thoại cá nhân, Wi-Fi, GPS và movement không xác định Entry/Exit. Một hệ
thống vật lý độc lập phát immutable event; BMA đối chiếu, ghép session và audit.

## Consequence

Alpha dùng fixture/schema thật nhưng không tính lương production. Chỉ session
được phê duyệt và có trace tới raw event mới được export bảng công.
