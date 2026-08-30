# Deployment và rollback

## Environments

| Environment | URL/port | Database | Dữ liệu |
| --- | --- | --- | --- |
| Local | `http://localhost:8790` | `bma_dev` | synthetic |
| Staging | `/bmapp-staging` | riêng | synthetic/anonymized |
| Production | `/bmapp` | riêng | production |

Không dùng chung database, secret hoặc refresh token giữa ba môi trường.

`App__PathBase` phải trùng chính xác prefix mà Cloudflare chuyển tiếp:

- Staging: `App__PathBase=/bmapp-staging`.
- Production: `App__PathBase=/bmapp`.

Cloudflare Tunnel giữ nguyên path; nó không tự đổi `/bmapp-staging` thành
`/bmapp`. Health, Admin, API và static assets đều được kiểm thử dưới prefix đã
cấu hình để tránh route đúng nhưng giao diện mất CSS.

Container bật xử lý `X-Forwarded-Proto` để redirect/cookie Admin nhận đúng HTTPS
do Cloudflare kết thúc TLS. Cổng BMA bắt buộc vẫn bind `127.0.0.1`; không đổi
thành `0.0.0.0`, vì đây là ranh giới tin cậy cho forwarded headers. Volume
`bma_dataprotection` giữ khóa cookie/antiforgery qua các lần restart.

## Local Docker

1. Copy `.env.example` thành `.env` và thay toàn bộ `CHANGE_ME`.
2. Chạy `docker compose --env-file .env up --build`.
3. Kiểm tra `/bmapp/health`, Admin login và stylesheet bằng
   `infra/scripts/health-check.ps1`.
4. Xóa/rotate bootstrap password sau khi admin đầu tiên được tạo.

## Host MinhComp

1. Backup PostgreSQL hiện tại và lưu manifest checksum.
2. Pull đúng commit đã qua CI.
3. Build image; chạy migration trong staging trước.
4. Health/smoke test bằng `infra/scripts/health-check.ps1`.
5. Chuyển Cloudflare route khi staging đạt.
6. Theo dõi log/outbox lag/HTTP 5xx tối thiểu 30 phút.

## Rollback

1. Chuyển Tunnel route về image/version trước.
2. Không downgrade database khi migration chỉ add table/column.
3. Nếu migration phá vỡ tương thích, restore database backup vào instance mới,
   verify checksum rồi mới đổi route.
4. Raw events nhận trong khoảng sự cố được replay từ Gateway history/cursor.

## Secrets

Các biến tối thiểu:

```text
ConnectionStrings__Bma
Jwt__SigningKey
Gateway__InboundKey
Gateway__HistoryKey
BMA_BOOTSTRAP_ADMIN_USERNAME
BMA_BOOTSTRAP_ADMIN_PASSWORD
```

Secret chỉ đặt trên host/CI console chính chủ, không paste vào chat hoặc commit.
