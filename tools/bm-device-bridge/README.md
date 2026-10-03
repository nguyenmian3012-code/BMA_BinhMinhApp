# BM Device Bridge v0.3.2

Bridge nhận callback HTTP từ Terminal qua LAN, commit dữ liệu gốc vào SQLite rồi mới trả `200 OK`. Khi bật staging, Bridge chuyển callback thành `EMPLOYEE_SCAN` trung tính và gửi HTTPS vào BMA. BMA quyết định Entry/Exit theo ca và session riêng của từng nhân viên. Terminal và Bridge không ghi PostgreSQL trực tiếp.

## Cấu hình đã khóa

- Terminal: `1605063` — `192.168.1.227`
- Máy Bridge: `MINHCOMP` — `192.168.1.99`
- Cổng nhận: `8789/TCP`
- SQLite: `data/bm-device-bridge.sqlite`
- BMA staging: `https://gateway.redtigerhead.com/bmapp-staging`
- Dahahi MQTT và firmware: giữ nguyên trong giai đoạn đối chứng

Luồng dữ liệu:

`Terminal -> BM Device Bridge -> BMA API -> PostgreSQL -> BMA mobile`

`nv.redtigerhead.com` là trang quản lý/phân phối Bridge, không phải endpoint nhận callback.

## 1. Nâng cấp an toàn và giữ Shadow

1. Dừng Bridge cũ bằng `Ctrl+C`.
2. Sao lưu nguyên thư mục `data`.
3. Chép đè các file chương trình v0.3.2, tuyệt đối không xóa `data`.
4. Chạy:

   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File .\start-shadow.ps1
   ```

5. Kiểm tra:

   ```powershell
   Invoke-RestMethod http://127.0.0.1:8789/health
   ```

Kết quả cần có `version: 0.3.2`, `mode: shadow-local-only`, heartbeat tiếp tục tăng và dữ liệu cũ còn nguyên.

## 2. Xuất mẫu callback để khóa parser

Bridge không đoán tên field mã người. Khi Terminal đã phát sinh lượt thử, chạy:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\export-shadow.ps1
```

File `data\shadow-sample.json` chứa tối đa 5 callback gần nhất. Dựa vào cấu trúc thật, xác định đường dẫn mã người, ví dụ `body.personId` hoặc `body.data.personId`. Nếu Terminal gửi thời gian/confidence, có thể xác định thêm đường dẫn tương ứng.

## 3. Tạo mapping Terminal -> BMA

Copy `employee-map.example.json` thành `employee-map.json`, rồi thay bằng mã thật:

```json
{
  "terminal_person_to_employee": {
    "<ID trên Terminal>": "<employee_code trong BMA>"
  }
}
```

Giá trị bên phải bắt buộc là `employee_code` trong BMA, không phải số điện thoại, user ID hoặc tên hiển thị.

## 4. Bật chuyển tiếp staging

Thay `body.personId` bằng field đã xác minh từ mẫu:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\start-staging.ps1 `
  -PersonField "body.personId"
```

Bridge mặc định bỏ lần nhận diện lặp cùng người và thiết bị trong 120 giây. Có thể hiệu chỉnh bằng `-DedupeSeconds`, từ `0` đến `3600`; `0` tắt chống trùng. Trường `direction` trong health phải là `AUTO`.

Script tự đọc `BMA_GATEWAY_INBOUND_KEY` từ `C:\ABMT\BMA_BinhMinhApp\.env.staging`; secret không được in ra màn hình.

Mặc định có van an toàn: callback đã thu trong Shadow được đánh dấu `shadowed` và không tự replay. Chỉ callback mới sau lần bật staging được gửi. Không dùng `-ReplayShadow` nếu chưa duyệt từng dữ liệu cũ.

## 5. Trạng thái và xử lý lỗi

```powershell
Invoke-RestMethod http://127.0.0.1:8789/health
```

- `sent`: BMA đã trả `202 ACCEPTED` hoặc `200 DUPLICATE`.
- `deduplicated`: callback lặp đã lưu raw nhưng không gửi lại BMA.
- `blocked`: sai mapping, parser, key hoặc contract; Bridge không retry vô hạn.
- `pending`: đang chờ gửi hoặc retry lỗi mạng/`429`/`5xx`.
- `shadowed`: dữ liệu cũ được giữ cục bộ nhưng chưa gửi.

`v0.3.2` che các header chứa key/token/secret/signature, giới hạn request HTTP,
và tự xóa callback đã xử lý quá 30 ngày. Các bản ghi `pending` hoặc `blocked`
không bị xóa. Chạy cleanup thủ công chỉ từ localhost:

```powershell
Invoke-RestMethod http://127.0.0.1:8789/control/cleanup -Method Post
```

Sau khi sửa mapping/parser, đưa các bản ghi `blocked` về hàng đợi:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\requeue-blocked.ps1
```

## 6. Cấu hình Terminal giữ nguyên

Trong **Thuê bao HTTP**:

| Trường | Giá trị |
| --- | --- |
| Loại giao thức | `LAN` |
| Địa chỉ dịch vụ | `192.168.1.99` |
| Cổng dịch vụ | `8789` |
| Đăng ký xác thực | Bật đăng ký |
| URL Nhịp Tim | `/Subscribe/heartbeat` |
| Chu kỳ xung nhịp | `30` giây |

Không thay firmware, không bật Kết nối trung tâm và chưa tắt MQTT `brokers.dahahi.vn` trong giai đoạn đối chứng.

## PostgreSQL đích

BMA nhận canonical event bằng `POST /api/v1/integrations/events`, lưu envelope vào `raw_integration_events`, sau đó projector quyết định Entry/Exit, ghi `attendance_events` và ghép `attendance_sessions`. Chỉ BMA API được ghi PostgreSQL.

## Ca Hành Chính mặc định

- Thứ Hai đến Thứ Bảy, Chủ Nhật nghỉ.
- Ca `07:00-17:00`; nghỉ trưa không tính công `11:00-13:00`.
- Nhận giờ vào từ `06:30` và giờ ra đến `17:20`.
- Đủ hai lượt được tính theo phút thực tế trong khung ca, tối đa `480` phút.
- Thiếu một lượt được BMA đối soát thành `240` phút (`50%`) và gắn cảnh báo để kiểm tra.
- Mỗi nhân viên có session theo ngày riêng; lượt của người này không đổi luồng của người khác.
