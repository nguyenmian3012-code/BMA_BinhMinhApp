import 'package:bma/core/bma_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local read state overrides a stale cached announcement', () {
    final data = <String, dynamic>{
      'items': <Map<String, dynamic>>[
        {'id': 'read-id', 'read_at': null},
        {'id': 'unread-id', 'read_at': null},
      ],
    };

    applyLocalAnnouncementReads(data, {'read-id'});

    final items = data['items'] as List<Map<String, dynamic>>;
    expect(items[0]['read_at'], 'LOCAL');
    expect(items[1]['read_at'], isNull);
  });
}
