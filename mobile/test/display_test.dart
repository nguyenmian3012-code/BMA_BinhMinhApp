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
}
