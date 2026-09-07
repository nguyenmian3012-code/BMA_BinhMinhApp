# BMA Data Dictionary V1

Quy ước: thời gian dùng ISO-8601 UTC trong API/DB; UI đổi sang
`Asia/Ho_Chi_Minh`. ID do source tạo phải ổn định qua retry.

## Canonical event envelope

| Field | Kiểu | Bắt buộc | Ý nghĩa |
| --- | --- | --- | --- |
| `event_id` | string ≤ 100 | Có | ID bất biến/idempotency từ source |
| `event_type` | enum | Có | Loại sự kiện canonical |
| `source_system` | string ≤ 64 | Có | `MOTORNODE`, `BMKCS`, `ENTRY_EXIT`, ... |
| `source_device_id` | string ≤ 100 | Không | Station/device phát sinh |
| `sequence` | int64 | Không | Chuỗi đơn điệu trong phạm vi thiết bị |
| `occurred_at` | datetime | Có | Thời gian vật lý ở source |
| `schema_version` | string | Có | Mặc định `1.0` |
| `correlation_id` | string | Không | Nối chuỗi retry/command |
| `payload` | object | Có | Nội dung theo event type |
| `payload_hash` | string | Có | SHA-256 của compact JSON payload theo thứ tự field schema |
| `signature` | string | Không | Chữ ký HMAC/asymmetric khi source hỗ trợ |

## Event types V1

| Event | Payload chính | Source |
| --- | --- | --- |
| `MOTOR_STATE_CHANGED` | `motor_id`, `position`, `state`, `heartbeat_at` | MotorNode |
| `QUALITY_RESULT_PUBLISHED` | `result_id`, `lot_code`, pH/white/moisture/fineness | BMKCS |
| `EMPLOYEE_ENTRY` | `employee_id`, `evidence_ref` | Entry/Exit độc lập |
| `EMPLOYEE_EXIT` | `employee_id`, `evidence_ref` | Entry/Exit độc lập |
| `PRODUCTION_MASS_RECORDED` | `period_id`, `kind`, `mass_kg`, `basis` | Nguồn cân duyệt |
| `ANNOUNCEMENT_PUBLISHED` | `announcement_id`, `audience`, `priority` | BMA Admin |

## Quality

| Field | Kiểu/unit | Ghi chú |
| --- | --- | --- |
| `ph` | decimal | Không unit |
| `whiteness` | decimal `%` | BMKCS published only |
| `moisture` | decimal `%` | Không nhận dữ liệu gram từ test device |
| `fineness` | decimal + unit | Field riêng, nullable tới khi source thật có |
| `viscosity` | decimal + unit | Không được đổi tên thành độ mịn |
| `extra_value` | decimal | Không được suy diễn ý nghĩa |
| `measured_at` | datetime | Thời điểm đo/publish nguồn |
| `freshness` | enum | `FRESH`, `STALE`, `UNKNOWN` |

Threshold baseline từ BMKCS hiện tại: pH 5.0–7.0; moisture 12.0–13.0%;
whiteness < 90.0% đỏ; whiteness ≥ 94.8% xanh. Đây là presentation rule và phải
version trước khi dùng để quyết định chất lượng/lương/phạt.

## Recovery

`recovery_percent = output_starch_mass / input_cassava_mass × 100`

Chỉ tính khi input/output cùng `period_id`, `basis`, formula version và đã được
duyệt. Nếu thiếu một vế, API trả `status=INSUFFICIENT_DATA` và `value=null`.

## Attendance

| Field | Kiểu | Ghi chú |
| --- | --- | --- |
| `employee_id` | string | Mã nhân viên, không phải device/phone ID |
| `kind` | enum | `ENTRY` hoặc `EXIT` |
| `evidence_ref` | string | Tham chiếu bằng chứng tại hệ thống độc lập |
| `session_status` | enum | `PROVISIONAL`, `CONFIRMED`, `NEEDS_REVIEW`, `APPROVED` |
| `payroll_approved_at` | datetime? | Bắt buộc trước export bảng lương |

Duplicate, sequence gap, đảo thứ tự, late arrival và thiếu cặp đều được lưu vào
audit/anomaly; không tự xóa hoặc sửa raw event.
