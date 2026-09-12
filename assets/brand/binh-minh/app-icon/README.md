# Bình Minh BM7 official app icon

Đây là nguồn icon chính thức dùng cho BMA và có thể tái sử dụng cho ứng dụng,
website hoặc PWA khác của Bình Minh. Màu nền chuẩn là `#E0000B`.

Nguồn audit: `BM7_AppIcon_Android_iOS.zip`, SHA-256
`fd6ff6f2e3e1a64484a78f3a1aa7c80ea8030ecd6a046d0f57ac8f80e993e018`.

## Cấu trúc đã tinh gọn

```text
source/                       Ảnh BM7 gốc để truy xuất nguồn
master/                       Master duy nhất cần giữ lâu dài
web/                          Favicon, Apple Touch Icon và PWA icon dùng ngay
platform/android/res/         Launcher, Adaptive và Themed Icon cho Android
platform/ios/AppIcon.appiconset/
                              Asset Catalog hoàn chỉnh cho iPhone/iPad
```

Các master:

- `master/app-icon-rounded-2048.png`: bản vuông bo góc, nền ngoài trong suốt;
  dùng để xuất thêm kích thước web/legacy.
- `master/android-adaptive-tiger-432.png`: đầu hổ trắng không kèm khung;
  dùng đồng thời cho foreground và monochrome của Android Adaptive Icon.
- iOS marketing master nằm tại
  `platform/ios/AppIcon.appiconset/Icon-App-1024x1024@1x.png`; file là RGB,
  không có alpha.

## Vì sao một số file trong ZIP gốc không được giữ

- `BM7_AppIcon_Rounded_Preview_1024.png`: có nền trắng để preview, không phải
  asset triển khai.
- `BM7_AppIcon_iOS_FullBleed_2048.png`: có kênh alpha dù mọi pixel đều opaque;
  không cần thiết và có thể gây lỗi kiểm duyệt App Store.
- Các bản `master/universal` 1024 trùng nội dung: chỉ giữ một nguồn chuẩn.
- `ic_launcher_round.*`: trùng byte với `ic_launcher.*`; Android Adaptive Icon
  tự áp dụng mask tròn/squircle nên không cần lưu bản sao.
- `ic_launcher_monochrome.*`: phần đầu hổ giống foreground; XML Android 13+
  tái sử dụng cùng resource thay vì nhân đôi năm density.
- Adaptive foreground có cả khung vuông sát mép: bị cắt thành các đoạn rời trên
  launcher dùng mask tròn. Bộ đã sửa chỉ giữ đầu hổ trong foreground.
- Thư mục `drawable-nodpi` rỗng và các kích thước trung gian có thể sinh lại.

Hai cặp PNG iOS 40 px và 120 px giống byte nhưng được giữ lại có chủ đích vì
chúng đại diện cho các slot iPhone/iPad khác nhau trong Asset Catalog. Tổng phần
lặp này chỉ khoảng 44 KB và giữ việc chép catalog vào Xcode đơn giản, ít lỗi.

## Áp dụng cho Flutter BMA

Sau khi tạo platform shell bằng `flutter create`, chạy từ root repository:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\infra\scripts\apply-mobile-branding.ps1 `
  -MobileRoot .\mobile
```

CI cũng gọi script này vào Android shell dùng một lần. Logo trong giao diện
Flutter sử dụng `mobile/assets/brand/bm7-app-icon.png`.

## Dùng cho website/PWA

- Browser favicon: `web/favicon-16.png`, `favicon-32.png`, `favicon-48.png`.
- Apple Touch Icon: `web/apple-touch-icon-180.png`.
- Web manifest/PWA: `web/pwa-icon-192.png`, `web/pwa-icon-512.png`.

Không bo góc thêm cho icon iOS, không đưa nền trắng vào launcher và không đổi
màu đỏ chuẩn nếu chưa có quyết định nhận diện thương hiệu mới.
