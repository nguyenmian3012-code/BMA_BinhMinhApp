import 'package:bma/models/display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unknown values never become a fake zero', () {
    expect(BmaDisplay.number(null, unit: '%'), 'Chưa có dữ liệu');
    expect(BmaDisplay.number(0, unit: '%'), '0.0%');
  });

  test('plant states preserve UNKNOWN semantics', () {
    expect(BmaDisplay.plantState('RUNNING'), 'Đang hoạt động');
    expect(BmaDisplay.plantState('UNKNOWN'), 'Không xác định');
  });

  test('attendance duration is displayed as hours and minutes', () {
    expect(BmaDisplay.durationMinutes(480), '8 giờ 00 phút');
    expect(BmaDisplay.durationMinutes(245), '4 giờ 05 phút');
    expect(BmaDisplay.durationMinutes(null), '0 giờ 00 phút');
  });

  test('missing attendance punch is explained in Vietnamese', () {
    expect(
      BmaDisplay.attendanceStatus('NEEDS_REVIEW', 'MISSING_EXIT'),
      'Thiếu giờ ra · tạm tính 50%',
    );
  });
}
