# Binh Minh App (BMA)

BMA là ứng dụng nội bộ chính thức của Bình Minh cho Android và iOS. Dự án dùng
Flutter cho mobile và một BMA Core độc lập chạy ASP.NET Core .NET 10 LTS,
PostgreSQL và Razor Pages Admin.

> Trạng thái: **Engineering Alpha đang triển khai theo Whitepaper V1.0**  
> Nhánh phát triển hiện tại: `codex/windows-native-runtime-v0-3-3`
> BMA Core: `v0.3.1`; BM Device Bridge mới nhất: `v0.3.2`
> Múi giờ nghiệp vụ: `Asia/Ho_Chi_Minh`  
> Package/bundle ID dự kiến: `com.binhminh.bma`

## Mục tiêu sản phẩm

1. Trạng thái hoạt động nhà máy, tổng giờ chạy và lịch chạy tương lai.
2. Chất lượng thành phẩm và tỷ lệ thu hồi có nguồn dữ liệu rõ ràng.
3. Chấm công cá nhân từ Terminal độc lập qua `EMPLOYEE_SCAN`.
4. Vai trò, trách nhiệm, nghĩa vụ, quyền lợi và trọng trách của nhân viên.
5. Thông báo cho toàn công ty, bộ phận, vai trò hoặc cá nhân.

## Quyết định kiến trúc đã khóa

- Flutter native, một codebase Android/iOS; không làm PWA rồi viết lại.
- BMA Core là modular monolith độc lập với ABMT AI Core, OpenClaw và 9Router.
- PostgreSQL là cơ sở dữ liệu trung tâm; Razor Pages Admin nằm cùng BMA Core.
- REST API có version; canonical event, idempotency, immutable raw event,
  transactional outbox, reconciliation cursor và audit là bắt buộc.
- MotorNode và BMKCS vẫn là source of record. BMA không scrape HTML dashboard.
- Điện thoại, Wi-Fi, GPS và movement không được dùng để xác định chấm công.
- BMA không cần AI và vẫn phải chạy bình thường khi toàn bộ AI bị tắt.
- Không commit secret, mật khẩu, station key, database thật hoặc signing key.

## Cấu trúc repository

```text
/mobile       Flutter application source
/backend      BMA Core API, workers, Admin và PostgreSQL migrations
/contracts    OpenAPI, JSON Schema và payload mẫu
/infra        Windows Service, Cloudflare, Gateway và script vận hành
/tools        BM Device Bridge và công cụ biên tại nhà máy
/docs         Whitepaper, ADR, data dictionary, roadmap và runbook
/assets       Tài sản nhận diện chính thức dùng lại cho app và website
```

## Một lệnh triển khai Terminal staging

Giải nén `BMA-Terminal-Stack-v0.3.2`, giữ nguyên `.env.staging`, `data` và
`employee-map.json`, rồi chạy:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Deploy-BMA-Terminal-v0.3.2.ps1
```

Script publish BMA thành Windows Service, kết nối PostgreSQL 17 native, kiểm tra
local/public, nâng cấp Bridge rồi requeue callback. Docker Desktop không còn
tham gia runtime trên MinhComp.

## Quy tắc chấm công `EMPLOYEE_SCAN`

Terminal chỉ xác nhận **ai** và **lúc nào**. Bridge lưu callback gốc vào SQLite,
map mã người sang `employee_code`, chống lặp trong 120 giây rồi gửi một canonical
event trung tính `EMPLOYEE_SCAN`. Bridge không gửi và không tự đoán `IN/OUT`.
Các event `EMPLOYEE_ENTRY/EMPLOYEE_EXIT` vẫn được BMA nhận để tương thích nguồn
cũ, nhưng không thuộc luồng Terminal/Bridge v0.3.2.

BMA phân loại riêng cho từng nhân viên và ngày làm việc theo giờ Việt Nam:

| Giờ nhận diện | Xử lý mặc định |
| --- | --- |
| `06:30-10:59` | Entry |
| `11:00-12:59` | Bỏ qua trong giờ nghỉ |
| `13:00-17:20` | Exit |
| Ngoài khung trên hoặc Chủ Nhật | Bỏ qua và ghi audit |

Lượt Entry mở session tạm. Lượt Exit hợp lệ đóng session và tính phút thực tế,
không tính nghỉ trưa `11:00-13:00`, tối đa 480 phút. Thiếu Entry hoặc Exit được
đánh dấu `NeedsReview` và tạm ghi 240 phút; dữ liệu này chưa được tự động dùng
cho bảng lương. Mỗi nhân viên có session độc lập nên lượt quét của người khác
không thay đổi hướng chấm công.

### Khả năng mở rộng ca cá nhân

BMA hiện chỉ dùng một **Ca Hành Chính** toàn cục từ cấu hình. Đây là giới
hạn hiện tại, không phải thiết kế cuối. `attendance_sessions.shift_code` đã lưu
mã ca, nên có thể mở rộng mà không đổi event `EMPLOYEE_SCAN`: thêm danh mục ca,
gán ca cho nhân viên theo khoảng hiệu lực, rồi resolve ca trước khi phân loại
Entry/Exit. Ca đêm và ngoại lệ theo ngày cần được kiểm thử riêng trước khi dùng
cho bảng lương.

Việc duyệt tài khoản có `employee_code` giờ chỉ thành công khi tìm thấy đúng hồ
sơ nhân viên chưa liên kết. Migration đi kèm tự gắn lại các tài khoản đã duyệt
với hồ sơ có cùng mã nhân viên.

## Endpoint dự kiến

| Route | Chức năng |
| --- | --- |
| `/bmapp/api/v1/*` | Mobile/Admin API |
| `/bmapp/api/v1/integrations/events` | Canonical event ingest |
| `/bmapp/admin/*` | Razor Pages Admin |
| `/bmapp/health` | Liveness/health |

URL kiểm tra hiện tại:

- Staging: `https://gateway.redtigerhead.com/bmapp-staging/health/details`
- Production: `https://gateway.redtigerhead.com/bmapp/health/details`

Các route hiện hữu được giữ nguyên:

- `/api/motornode/*` và dashboard `/motornode`
- `/api/bmkcslab/*` và dashboard `/bmkcs`

Tình trạng publish BMKCS hiện tại được ghi tại
[`docs/BMKCS_PUBLISH_AUDIT.md`](docs/BMKCS_PUBLISH_AUDIT.md).

## Chạy backend native

Yêu cầu: PostgreSQL 17 native. Có thể dùng package `bma-native-win-x64` từ CI;
nếu không có package, máy triển khai cần .NET 10 SDK.

```powershell
Copy-Item .env.example .env.staging
# Điền secret trong .env.staging; không commit file này.
powershell.exe -ExecutionPolicy Bypass `
  -File .\infra\scripts\restore-staging-origin.ps1
```

Staging chạy service `BMA-Staging`, port `8791`, database native
`binhminh_data_staging`. Production dùng service `BMA-Production`, port `8790`,
database `binhminh_data`. Hai môi trường không dùng chung database hoặc secret.

## Chạy Flutter local

Yêu cầu: Flutter stable và Android SDK. Lần đầu cần tạo platform shell:

```powershell
Set-Location mobile
flutter create --platforms=android,ios --org com.binhminh --project-name bma .
flutter pub get
flutter run --dart-define=BMA_API_BASE_URL=http://10.0.2.2:8790/bmapp/api/v1
```

CI tạo Android shell trong thư mục tạm, áp dụng BM7 official launcher icon,
phân tích mã, chạy test và build profile APK arm64 trỏ staging; source Flutter
trong repo không phụ thuộc file platform sinh tự động để review gọn.
Artifact GitHub chỉ là tiện ích tạm thời và không chặn CI nếu quota tài khoản đã
đầy. Kênh phát hành bền vững là APK/AAB đã ký qua `/bmapp/download` hoặc Store.

## Tiêu chuẩn dữ liệu quan trọng

- Tỷ lệ thu hồi chỉ được tính khi có khối lượng khoai đầu vào và tinh bột đầu ra
  cùng kỳ/cùng basis. Thiếu dữ liệu trả về `Chưa đủ dữ liệu`, không trả `0` giả.
- Độ mịn là field riêng; không đổi tên `viscosity` hoặc `extra_value` thành độ mịn.
- Duplicate event trả kết quả idempotent và không tạo duplicate record.
- Chỉ attendance session đã được phê duyệt mới được dùng cho bảng lương.

## Tài liệu chính

- [Whitepaper V1.0](docs/BMA_Whitepaper_V1.0_2026-08-30.txt)
- [Kiến trúc](docs/ARCHITECTURE.md)
- [Data dictionary](docs/DATA_DICTIONARY.md)
- [Gateway integration](docs/GATEWAY_INTEGRATION.md)
- [Triển khai và rollback](docs/DEPLOYMENT.md)
- [Nhật ký phân tích lỗi build](docs/BUILD_TROUBLESHOOTING.md)
- [Các bước thủ công của chủ hệ thống](docs/OWNER_ACTIONS.md)
- [Kế hoạch ABMT Remote v1.1](docs/ABMT_REMOTE_V1_1_PLAN.md)
- [Roadmap](docs/ROADMAP.md)
- [BM7 official app icon](assets/brand/binh-minh/app-icon/README.md)

## Definition of Done cho Engineering Alpha

- Backend build/test, migration và Windows native package vượt CI.
- Flutter analyze/test và Android debug APK vượt CI.
- Auth hỗ trợ đăng ký chờ duyệt, phiên dài hạn có refresh-token rotation.
- Canonical event ingest, outbox, projection, audit và reconciliation có test.
- Năm luồng mobile đọc được API/fixture và thể hiện trạng thái dữ liệu cũ.
- Không có secret trong Git; staging/production có database và secret riêng.

Copyright © 2026 Bình Minh. Mã nguồn được công khai để review; chưa cấp license
sử dụng hoặc phân phối.
