# ADR-0002: Attendance source độc lập

- Status: Accepted
- Date: 2026-08-30

## Decision

Điện thoại cá nhân, Wi-Fi, GPS và movement không xác định Entry/Exit. Terminal
vật lý phát `EMPLOYEE_SCAN` bất biến qua Bridge. BMA đối chiếu ca và session của
từng nhân viên, quyết định Entry/Exit, ghép session và audit trong PostgreSQL.

## Consequence

Alpha dùng fixture/schema thật nhưng không tính lương production. Chỉ session
được phê duyệt và có trace tới raw event mới được export bảng công.
