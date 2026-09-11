# BMKCS publish audit — 2026-09-11

Nguồn được rà: `BMKCSLab_MVP_Source_V2.3_UI_COMM_PRINT_NET8_2026-08-12`.

## Kết luận

- Nút Publish ghi `published_results` và `outbox` trong cùng transaction SQLite.
- Client retry các outbox chưa ACK và chỉ đánh dấu `SYNCED` sau HTTP 2xx.
- BMA nhận và project được canonical event `QUALITY_RESULT_PUBLISHED`; CI có synthetic gate cho đường này.
- BMKCS v2.3 **chưa thể gọi thẳng BMA Integration API**: URL mặc định còn là
  `https://gateway.abmtlab.com/api/bmkcslab/v1/results`, payload vẫn dùng field
  rút gọn cũ và request không gửi `X-BMA-Gateway-Key`.

Vì vậy local publish/outbox là **CODE READY**. Luồng
`BMKCS → Gateway adapter → BMA → PostgreSQL → mobile` vẫn **NOT VERIFIED**.

## Adapter bắt buộc

Gateway phải đổi payload BMKCS thành canonical schema `1.0`:

| BMKCS v2.3 | BMA canonical |
| --- | --- |
| `id` | `payload.result_id` |
| `lot` | `payload.lot_code` |
| `ts` | `payload.measured_at` |
| `ph` | `payload.ph` |
| `w` | `payload.whiteness` |
| `m` | `payload.moisture` |
| `v` | `payload.viscosity` |
| `x` | `payload.extra_value` |
| `prod/op/qc/cust` | `product_code/operator_code/quality_code/customer_code` |
| `station` | `source_device_id` |

Adapter cũng phải tạo `event_id`, SHA-256 `payload_hash`, gửi
`Idempotency-Key` và secret `X-BMA-Gateway-Key`, rồi chuyển đúng HTTP 2xx về
BMKCS. Không được đánh dấu BMKCS `SYNCED` chỉ vì một endpoint cũ nhận request.

## Gate còn lại tại host

1. Publish một mẫu BMKCS.
2. Xác nhận outbox chuyển `PENDING → SYNCED`.
3. Xác nhận `raw_integration_events` có `QUALITY_RESULT_PUBLISHED`.
4. Xác nhận `quality_readings` có đúng `result_id`.
5. Mở màn Quality trên mobile.
