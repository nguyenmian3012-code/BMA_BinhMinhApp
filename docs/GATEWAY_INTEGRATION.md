# Gateway Integration Contract

## Hiện trạng đã xác minh từ source được cung cấp

- BMKCS Lab ghi `published_results` và `outbox` trong cùng SQLite transaction.
- Endpoint hiện tại: `POST /api/bmkcslab/v1/results`.
- Payload cũ viết tắt: `id`, `lot`, `ts`, `pd`, `prod`, `op`, `qc`, `cust`,
  `ph`, `w`, `m`, `v`, `x`, `station`.
- MotorNode ingest hiện tại: `POST /api/motornode/events`.
- Repo ABMT freeze chưa chứa source Gateway production, vì vậy chưa được phép
  tuyên bố Gateway outbox đã deploy.

## Hướng tích hợp chính thức

BMKCS v2.3 tạm tiếp tục publish vào endpoint cũ:

`POST https://gateway.abmtlab.com/api/bmkcslab/v1/results`

Gateway chỉ ACK sau khi raw record và integration outbox đã commit cùng
transaction. Dispatcher dùng
[`infra/gateway/bmkcs-adapter.mjs`](../infra/gateway/bmkcs-adapter.mjs) để đổi
payload cũ, rồi gửi canonical event tới:

`POST https://gateway.redtigerhead.com/bmapp/api/v1/integrations/events`

Headers:

```text
X-BMA-Gateway-Key: <secret on host>
Idempotency-Key: <event_id>
Content-Type: application/json
```

Response `202 accepted` hoặc `200 duplicate` đều là terminal success. `400/401/
403/409/422` phải quarantine/đòi can thiệp, không retry vô hạn. Chỉ timeout,
`408`, `429` và `5xx` được retry exponential backoff + jitter.

## BMKCS mapping

| Payload cũ | Canonical |
| --- | --- |
| `id` | envelope `event_id`, payload `result_id` |
| `ts` | `occurred_at`, payload `measured_at` |
| `pd` | `payload.production_date` (raw/audit) |
| `station` | `source_device_id` |
| `lot` | `payload.lot_code` |
| `ph` | `payload.ph` |
| `w` | `payload.whiteness` |
| `m` | `payload.moisture` |
| `v` | `payload.viscosity` |
| `x` | `payload.extra_value` |
| `prod` | `payload.product_code` |
| `op` | `payload.operator_code` |
| `qc` | `payload.quality_code` |
| `cust` | `payload.customer_code` |

`fineness` chỉ được set khi BMKCS phát field riêng. Không map `v` hoặc `x` sang
fineness.

Chạy contract/synthetic adapter test:

```text
node infra/gateway/bmkcs-adapter-test.mjs
```

Module mapping đã có trong repo. Source ABMT Gateway production chưa có trong
repo, nên phần gắn handler/outbox vào endpoint public vẫn cần source đang chạy
trên MinhComp.

## MotorNode mapping

Source event phải giữ ID thiết bị, vị trí `INPUT|OUTPUT`, trạng thái `ON|OFF`,
source timestamp, sequence và heartbeat. Mất heartbeat phát `DEVICE_STALE` hoặc
để BMA tính `UNKNOWN`; Gateway không tự tạo `OFF` giả.

## Reconciliation API cần thêm vào Gateway

```http
GET /api/bma/v1/integration-events?cursor=<opaque>&limit=100
```

Response:

```json
{
  "items": [],
  "next_cursor": "opaque",
  "has_more": false
}
```

Cursor là opaque và chỉ advance sau khi BMA commit toàn bộ page. BMA worker mặc
định tắt cho tới khi endpoint và secret thật được cấu hình.

Chi tiết triển khai phía Gateway nằm tại
[`infra/gateway/OUTBOX_PATCH.md`](../infra/gateway/OUTBOX_PATCH.md).

## BM Face Terminal 1605063 qua BM Device Bridge

Terminal chỉ gọi listener LAN `192.168.1.99:8789`. Bridge commit callback gốc
vào SQLite trước khi ACK, sau đó gửi canonical event qua HTTPS tới staging:

`POST https://gateway.redtigerhead.com/bmapp-staging/api/v1/integrations/events`

Bridge dùng đúng `X-BMA-Gateway-Key` và `Idempotency-Key`. ID người trên
Terminal phải được map tường minh sang `employee_code` BMA; không dùng tên hiển
thị, điện thoại hoặc device ID làm `employee_id`. Bridge v0.3 phát
`EMPLOYEE_SCAN` trung tính để một Terminal phục vụ đồng thời mọi nhân viên.

BMA quyết định Entry/Exit theo `employee_id`, ngày làm việc và khung Ca Hành
Chính: Thứ Hai-Thứ Bảy, `07:00-17:00`, nghỉ không tính công `11:00-13:00`, vào
sớm tối đa 30 phút và ra muộn tối đa 20 phút. Thiếu một lượt được đối soát thành
50% ca (`240` phút mặc định) và gắn `MISSING_ENTRY` hoặc `MISSING_EXIT`.

Mỗi canonical event được lưu vào `raw_integration_events`. Outbox projector ghi
`attendance_events` và ghép một `attendance_sessions` cho mỗi nhân viên/ngày
trong PostgreSQL. Terminal và Bridge không có tài khoản SQL; BMA API là writer
duy nhất để giữ validation, idempotency và audit tại cùng biên giao dịch.

Kiểm tra toàn bộ ba lớp dữ liệu trên máy staging:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\ops\verify-attendance-pipeline.ps1
```

Trong giai đoạn shadow, MQTT Dahahi và firmware được giữ nguyên. Lần đầu bật
forwarding không tự replay callback cũ; chỉ sự kiện mới sau activation được gửi.
