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

  static String plantState(Object? value) => switch (value) {
    'STARTING' => 'Đang khởi động',
    'RUNNING' => 'Đang hoạt động',
    'DRAINING' => 'Đang hoàn tất đầu ra',
    'STOPPED' => 'Đã dừng',
    _ => 'Không xác định',
  };
}
