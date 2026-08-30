# Nhật ký phân tích build BMA

Tài liệu này lưu nguyên nhân gốc và bản sửa cụ thể; không dùng cách chạy lại mù.

| Vòng CI | Triệu chứng | Nguyên nhân gốc | Bản sửa | Kết quả kiểm chứng |
| --- | --- | --- | --- | --- |
| 1 | Test .NET không nhận `Fact`/`Theory` | Test project thiếu global namespace Xunit | Thêm `GlobalUsings.cs` với `global using Xunit;` | Backend build và 12/12 test qua |
| 2 | Docker báo `NETSDK1064` cho analyzer dù restore thành công | `obj/project.assets.json` từ runner ghi đè assets đã restore trong container | Thêm `.dockerignore` loại toàn bộ `bin/obj` khỏi build context | Docker production image build qua |
| 2 | Flutter analyze báo `unawaited_return_in_try_block` | Nhánh retry refresh token trả `Future` trong `try` mà thiếu `await` | Đổi thành `return await _send(...)` | Flutter analyze và 3/3 test qua |
| 3 | APK build qua nhưng `upload-artifact` thất bại | Quota GitHub Actions artifact của tài khoản đã đầy; không phải lỗi Android | Bắt buộc kiểm tra file + SHA-256, đặt upload là tiện ích không chặn, retention 1 ngày | Build APK vẫn là quality gate; phát hành chính qua host/Store |

## Khi artifact GitHub không xuất hiện

1. Mở **GitHub Settings → Billing and licensing → Actions** để kiểm tra quota.
2. Chỉ xóa artifact cũ khi đã xác nhận không còn cần; quota có thể cập nhật chậm
   6–12 giờ.
3. Không commit APK vào Git. Bản Alpha có chữ ký phải được chép vào thư mục phát
   hành trên MinhComp và phục vụ qua HTTPS, ví dụ `/bmapp/download`.
4. Ghi SHA-256 và phiên bản cạnh file tải xuống để người cài đặt đối chiếu.

## Nguyên tắc

- Lỗi build/test là chặn phát hành.
- Lỗi kênh upload phụ không được giả thành lỗi mã nguồn, nhưng phải hiện warning.
- Bản Store phải dùng signing của Bình Minh; debug APK không phải bản production.
