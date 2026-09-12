# Gateway transactional outbox patch specification

Áp dụng vào source Gateway production sau khi Anh cung cấp đúng file/repo đang
chạy. Không patch bản freeze placeholder.

## Tables

```sql
CREATE TABLE integration_outbox (
  id TEXT PRIMARY KEY,
  source_system TEXT NOT NULL,
  source_event_id TEXT NOT NULL,
  event_type TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  payload_hash TEXT NOT NULL,
  occurred_at TEXT NOT NULL,
  sequence INTEGER,
  attempt_count INTEGER NOT NULL DEFAULT 0,
  next_attempt_at TEXT NOT NULL,
  delivered_at TEXT,
  last_error TEXT,
  quarantine_reason TEXT,
  UNIQUE(source_system, source_event_id)
);
```

SQLite/PostgreSQL syntax được điều chỉnh theo DB thật. Record nguồn và outbox
phải insert trong cùng transaction trước khi trả ACK cho M1-P/BMKCS.

## Dispatcher policy

1. Lấy tối đa 20 row đến hạn, theo `occurred_at,id`.
2. POST canonical event với `Idempotency-Key` và `X-BMA-Gateway-Key`.
3. `200/202`: set `delivered_at`.
4. Timeout/408/429/5xx: retry exponential `min(5m, 2^attempt)` + jitter.
5. 400/401/403/409/422: quarantine; không retry vô hạn.
6. Chỉ một dispatcher flush tại một thời điểm.

## History/cursor

`GET /api/bma/v1/integration-events?cursor=&limit=100` đọc từ bảng sự kiện bền
vững, không đọc dashboard. Cursor chứa thứ tự `(occurred_at,id)` đã ký/opaque.

## BMKCS client fix riêng

Client V2.3 hiện gọi `EnsureSuccessStatusCode()` nên mọi 4xx đều thành retry.
Khi cập nhật LabStation, phân loại terminal/retry như trên, thêm station headers
trên host và khóa single-flush để tránh gửi song song.
