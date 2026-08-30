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

Gateway tiếp tục ACK source sau khi raw record và integration outbox đã commit
cùng transaction. Một dispatcher gửi canonical event tới:

`POST https://gateway.abmtlab.com/bmapp/api/v1/integrations/events`

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
| `station` | `source_device_id` |
| `lot` | `payload.lot_code` |
| `ph` | `payload.ph` |
| `w` | `payload.whiteness` |
| `m` | `payload.moisture` |
| `v` | `payload.viscosity` |
| `x` | `payload.extra_value` |

`fineness` chỉ được set khi BMKCS phát field riêng. Không map `v` hoặc `x` sang
fineness.

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
