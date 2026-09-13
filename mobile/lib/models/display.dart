class BmaDisplay {
  static String number(Object? value, {int digits = 1, String unit = ''}) {
    if (value is! num) return 'Chưa có dữ liệu';
    return '${value.toDouble().toStringAsFixed(digits)}$unit';
  }

  static String dateTime(Object? value) {
    if (value is! String) return 'Chưa có dữ liệu';
    final parsed = DateTime.tryParse(value)?.toLocal();
    if (parsed == null) return 'Chưa có dữ liệu';
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(parsed.hour)}:${two(parsed.minute)} '
        '${two(parsed.day)}/${two(parsed.month)}/${parsed.year}';
  }

  static String date(Object? value) {
    if (value is! String) return '--/--/----';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return '--/--/----';
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(parsed.day)}/${two(parsed.month)}/${parsed.year}';
  }

  static String time(Object? value) {
    if (value is! String) return '--:--';
    final parsed = DateTime.tryParse(value)?.toLocal();
    if (parsed == null) return '--:--';
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(parsed.hour)}:${two(parsed.minute)}';
  }

  static String durationMinutes(Object? value) {
    if (value is! num) return '0 giờ 00 phút';
    final total = value.toInt().clamp(0, 1000000);
    final minutes = (total % 60).toString().padLeft(2, '0');
    return '${total ~/ 60} giờ $minutes phút';
  }

  static String attendanceStatus(Object? status, Object? reason) => switch (reason) {
    'MISSING_ENTRY' => 'Thiếu giờ vào · tạm tính 50%',
    'MISSING_EXIT' => 'Thiếu giờ ra · tạm tính 50%',
    _ => switch (status) {
      'CONFIRMED' => 'Đủ lượt vào/ra',
      'PROVISIONAL' => 'Đã vào · chờ giờ ra',
      'APPROVED' => 'Đã duyệt',
      'NEEDS_REVIEW' => 'Cần kiểm tra',
      _ => 'Chưa xác định',
    },
  };

  static String plantState(Object? value) => switch (value) {
    'STARTING' => 'Đang khởi động',
    'RUNNING' => 'Đang hoạt động',
    'DRAINING' => 'Đang hoàn tất đầu ra',
    'STOPPED' => 'Đã dừng',
    _ => 'Không xác định',
  };
}
