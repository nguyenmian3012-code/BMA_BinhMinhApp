# ABMT Remote v1.1 — kế hoạch nâng cấp

## Phạm vi

Một ứng dụng điều khiển, hai nhóm độc lập. Không trộn API, database hoặc secret.

| Nhóm | Dịch vụ |
| --- | --- |
| ABMT | 9Router, OpenClaw, ABMT Core, Cloudflare ABMT, các channel hiện hữu |
| Bình Minh | PostgreSQL 17 native, Windows Service BMA production `8790`, staging `8791`, BM Device Bridge `8789`, RedTiger tunnel, BMKCS Lab |

Mỗi dịch vụ hiển thị ba tín hiệu riêng: process/service Windows, local health,
public health. `Cloudflare Online` không đồng nghĩa origin hoạt động; public
`502` phải hiển thị đỏ dù process cloudflared vẫn chạy.

## Thay đổi v1.1

- Thêm tab/nhóm `Bình Minh`.
- Nút riêng: Start/Stop ABMT và Start/Stop Bình Minh.
- Link nhanh: BMA Admin, RedTiger health, Bridge health.
- Probe local/public độc lập, timeout 5 giây.
- Không đặt secret trong UI hoặc source. Chỉ gọi script đã đọc env trên host.
- Không dừng PostgreSQL khi bấm Stop Bình Minh nếu chưa có xác nhận riêng.

## Blocker source

Source ABMT Remote v1.0 chưa có trong repository BMA hoặc ABMT_task. Trên
MinhComp, chạy lệnh sau và gửi lại output; không gửi file `.env`:

```powershell
Get-ChildItem C:\ABMT -Recurse -File -Include *.sln,*.csproj,*.cs |
  Where-Object { $_.FullName -notmatch '\\(bin|obj)\\' } |
  Select-String -Pattern 'ABMT Remote|Designed by Minh An|Start Service' |
  Select-Object -First 30 Path,LineNumber,Line
```

Sau khi có đúng folder/repo, cập nhật WinForms tại chỗ, giữ cấu trúc v1.0 và
đóng gói v1.1. Không viết lại framework.
