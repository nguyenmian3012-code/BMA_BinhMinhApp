# Binh Minh App (BMA)

BMA là ứng dụng nội bộ chính thức của Bình Minh cho Android và iOS. Dự án dùng
Flutter cho mobile và một BMA Core độc lập chạy ASP.NET Core .NET 10 LTS,
PostgreSQL và Razor Pages Admin.

> Trạng thái: **Engineering Alpha đang triển khai theo Whitepaper V1.0**  
> Múi giờ nghiệp vụ: `Asia/Ho_Chi_Minh`  
> Package/bundle ID dự kiến: `com.binhminh.bma`

## Mục tiêu sản phẩm

1. Trạng thái hoạt động nhà máy, tổng giờ chạy và lịch chạy tương lai.
2. Chất lượng thành phẩm và tỷ lệ thu hồi có nguồn dữ liệu rõ ràng.
3. Chấm công cá nhân từ hệ thống Entry/Exit độc lập.
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
/infra        Docker, Cloudflare, Gateway và script vận hành
/docs         Whitepaper, ADR, data dictionary, roadmap và runbook
```

## Endpoint dự kiến

| Route | Chức năng |
| --- | --- |
| `/bmapp/api/v1/*` | Mobile/Admin API |
| `/bmapp/api/v1/integrations/events` | Canonical event ingest |
| `/bmapp/admin/*` | Razor Pages Admin |
| `/bmapp/health` | Liveness/health |

Các route hiện hữu được giữ nguyên:

- `/api/motornode/*` và dashboard `/motornode`
- `/api/bmkcslab/*` và dashboard `/bmkcs`

## Chạy backend local

Yêu cầu: .NET 10 SDK, Docker Desktop và PostgreSQL/Docker Compose.

```powershell
Copy-Item .env.example .env
# Điền secret chỉ trong .env local; không commit file này.
docker compose --env-file .env up --build
Invoke-RestMethod http://localhost:8790/bmapp/health
```

## Chạy Flutter local

Yêu cầu: Flutter stable và Android SDK. Lần đầu cần tạo platform shell:

```powershell
Set-Location mobile
flutter create --platforms=android,ios --org com.binhminh --project-name bma .
flutter pub get
flutter run --dart-define=BMA_API_BASE_URL=http://10.0.2.2:8790/bmapp/api/v1
```

CI tạo Android shell trong thư mục tạm, phân tích mã, chạy test và build debug
APK; source Flutter trong repo không phụ thuộc file sinh tự động để review gọn.

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
- [Các bước thủ công của chủ hệ thống](docs/OWNER_ACTIONS.md)
- [Roadmap](docs/ROADMAP.md)

## Definition of Done cho Engineering Alpha

- Backend build/test, migration và Docker image vượt CI.
- Flutter analyze/test và Android debug APK vượt CI.
- Auth hỗ trợ đăng ký chờ duyệt, phiên dài hạn có refresh-token rotation.
- Canonical event ingest, outbox, projection, audit và reconciliation có test.
- Năm luồng mobile đọc được API/fixture và thể hiện trạng thái dữ liệu cũ.
- Không có secret trong Git; staging/production có database và secret riêng.

Copyright © 2026 Bình Minh. Repository riêng, không cấp license phân phối công khai.
