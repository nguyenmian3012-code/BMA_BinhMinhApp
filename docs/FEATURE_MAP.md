# BMA feature map — đối chiếu Whitepaper V1.0

Kiểm kê ngày 13/09/2026. Baseline: [`BMA_Whitepaper_V1.0_2026-08-30.txt`](BMA_Whitepaper_V1.0_2026-08-30.txt), mục 1, 4 và Alpha/Production Gate mục 6. Bằng chứng code tính đến commit `1e0df64` và CI #39; trạng thái MinhComp dựa trên output chủ máy. **CI xanh không đồng nghĩa staging, điện thoại hoặc nhà máy đã PASS.**

| Nhóm Whitepaper | Code/CI | Máy thật / nghiệp vụ | Gate kế tiếp |
| --- | --- | --- | --- |
| Flutter Android, đăng nhập và session | Năm màn, auth, cache, APK arm64 có CI PASS (`mobile/`, `.github/workflows/ci.yml`) | Chưa xác nhận APK mới trên điện thoại | Cài đúng artifact, đăng nhập, offline/logout |
| Nhà máy và lịch chạy | Motor projection, heartbeat stale → `UNKNOWN`, runtime/TOU, lịch Admin có code (`Modules/PlantStateCalculator.cs`, `Modules/ReadModelServices.cs`) | Nguồn INPUT/OUTPUT sống chưa được kiểm chứng sau chuyển runtime; `UNKNOWN` chưa chứng minh lỗi thuật toán | Verify hai heartbeat, trạng thái màn Overview |
| Chất lượng BMKCS | Canonical projection + adapter test synthetic PASS (`infra/gateway/bmkcs-adapter*`, `Modules/ApiEndpoints.cs`) | Adapter/outbox chưa xác nhận được gắn vào Gateway thật; desktop Publish → mobile chưa PASS | Publish mẫu thật, xác nhận outbox, raw event, `quality_readings`, mobile |
| Tỷ lệ thu hồi | Mass event, read model và `INSUFFICIENT_DATA` có code (`Integration/CanonicalEventProjector.cs`, `Modules/ReadModelServices.cs`) | Chưa có nguồn khối lượng đầu vào/đầu ra được duyệt | Khóa source, basis và formula trước dữ liệu thật |
| Chấm công | `EMPLOYEE_SCAN`, tự phân loại, idempotency, session synthetic CI PASS (`Integration/AttendancePolicy.cs`, `.github/workflows/ci.yml`) | Staging host chưa chạy; quét Terminal thật và hiển thị mobile chưa xác minh | Synthetic trên staging, rồi thử thiết bị thật; không dùng tính lương |
| Ca cá nhân, duyệt công | Một ca cấu hình chung cùng ngày; `ApprovedAt` là trường dữ liệu (`AttendancePolicy.cs`, `Domain/Entities.cs`) | Chưa có gán ca theo người/lịch, ca đêm, request adjustment và luồng HR duyệt công | Đặc tả ca, lưu assignment có hiệu lực, duyệt và audit |
| Hồ sơ và vai trò | Ràng buộc account–employee khi duyệt + migration, `/profile/me` (`Authentication/AuthService.cs`, migration `202609110001`) | `EMPLOYEE_PROFILE_NOT_LINKED` của tài khoản thật chưa được kiểm chứng sau deploy | Kiểm tra mapping tài khoản pilot, Profile/Attendance cùng người |
| Thông báo | Inbox, phân audience, read/unread, Admin publish (`Modules/ApiEndpoints.cs`, `Pages/Admin/Announcements`) | Tin trên Android cũ đã PASS; bản mới cần thử lại | Test tin, read/unread; FCM/APNs push còn thiếu |
| Gateway durability | BMA có raw event + outbox + worker; BMKCS mapper có test (`Integration/`, `infra/gateway/`) | Transactional outbox của Gateway và đường MotorNode/BMKCS public chưa được chứng thực | Lấy source Gateway đang chạy, gắn adapter/outbox, thử retry |
| Host/PostgreSQL/health | Native deploy script, CI backend/Android PASS; CI chưa từng khởi tạo service trên MinhComp | PostgreSQL 17.11 chạy, tạo staging DB PASS; tạo Windows Service FAIL ở `sc.exe config`; public health chưa PASS | Sửa đăng ký service, check local, rồi public |
| Backup, security, no-AI | Auth, scoped read, key management, backup/restore script có code | Native backup/restore, role/security và tắt OpenClaw khi test chưa xác nhận trên host | Restore DB tạm, test quyền và độc lập AI |
| Store-ready | APK alpha có build | Chưa có pilot Android đầy đủ, iOS signing/TestFlight, push, privacy policy, Store gates | Để sau Alpha; không gọi production |

## Gate thực tế

- **Code/CI:** PASS có điều kiện; CI #39 không kiểm tra Windows Service trên MinhComp.
- **Staging 8791:** BLOCKED tại `sc.exe config`, sau khi PostgreSQL native PASS; production `binhminh_data` không bị chuyển đổi bởi bước này.
- **Alpha end-to-end:** NOT PASS. Mới có fixture/synthetic tại CI, chưa có public health + APK trên điện thoại.
- **Production Gate:** NOT READY. Entry/Exit vật lý, duyệt công, restore, push và mobile/iOS còn thiếu.

## Luồng công việc không phụ thuộc Windows Service

Kiểm tra ca cá nhân, approval/adjustment, Profile UI, audit phân quyền, BMKCS mapper và gateway outbox, push plan, Android widget tests. Không báo các hạng mục này hoàn thành chỉ nhờ CI backend.

## Change control cần anh xác nhận

Whitepaper V1.0 vẫn ghi `gateway.abmtlab.com`, `EMPLOYEE_ENTRY/EXIT` và Docker tùy chọn. Những quyết định phát triển sau đã đổi BMA public sang `gateway.redtigerhead.com`, Bridge phát `EMPLOYEE_SCAN`, runtime sang PostgreSQL/Windows Service native. Giữ nguyên bản gốc; lập amendment V1.1 kèm ngày/phê duyệt trước khi coi các thay đổi này là baseline chính thức.
