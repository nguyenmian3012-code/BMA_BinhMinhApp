import 'package:flutter/material.dart';

import '../core/bma_repository.dart';
import '../models/display.dart';
import '../widgets/cached_view.dart';

class AttendanceScreen extends StatelessWidget {
  const AttendanceScreen({required this.repository, super.key});

  final BmaRepository repository;

  @override
  Widget build(BuildContext context) => CachedView(
    load: repository.attendance,
    builder: (context, data) {
      final items = (data['items'] as List? ?? const []).whereType<Map<String, dynamic>>().toList();
      return [
        const Card(
          child: ListTile(
            leading: Icon(Icons.verified_user_outlined),
            title: Text('Nguồn Entry/Exit độc lập'),
            subtitle: Text('Điện thoại, Wi-Fi và GPS không được dùng để xác định chấm công.'),
          ),
        ),
        if (items.isEmpty)
          const Card(child: ListTile(title: Text('Chưa có dữ liệu chấm công.')))
        else
          ...items.map((item) => Card(
            child: ListTile(
              leading: Icon(item['status'] == 'NEEDS_REVIEW' ? Icons.report_problem_outlined : Icons.access_time),
              title: Text('${BmaDisplay.dateTime(item['entry_at'])} → ${BmaDisplay.dateTime(item['exit_at'])}'),
              subtitle: Text('${item['status']}${item['review_reason'] == null ? '' : ' · ${item['review_reason']}'}'),
              trailing: item['payroll_approved'] == true
                  ? const Icon(Icons.verified, color: Colors.green)
                  : const Icon(Icons.hourglass_empty),
            ),
          )),
      ];
    },
  );
}
