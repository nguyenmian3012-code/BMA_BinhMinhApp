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
        Card(
          child: ListTile(
            leading: const Icon(Icons.calendar_month_outlined),
            title: Text('Tổng công tháng ${data['month'] ?? '--'}'),
            subtitle: Text(data['shift_name']?.toString() ?? 'Ca làm việc'),
            trailing: Text(
              BmaDisplay.durationMinutes(data['monthly_total_minutes']),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
        const Card(
          child: ListTile(
            leading: Icon(Icons.verified_user_outlined),
            title: Text('Terminal độc lập · tự phân loại'),
            subtitle: Text('Bridge gửi EMPLOYEE_SCAN; BMA quyết định Entry/Exit theo ca.'),
          ),
        ),
        if (items.isEmpty)
          const Card(child: ListTile(title: Text('Chưa có dữ liệu chấm công.')))
        else
          ...items.map((item) => Card(
            child: ListTile(
              leading: Icon(
                item['status'] == 'NEEDS_REVIEW'
                    ? Icons.report_problem_outlined
                    : Icons.access_time,
              ),
              title: Text(
                '${BmaDisplay.date(item['work_date'])} · '
                '${BmaDisplay.time(item['entry_at'])} → ${BmaDisplay.time(item['exit_at'])}',
              ),
              subtitle: Text(BmaDisplay.attendanceStatus(
                item['status'],
                item['review_reason'],
              )),
              trailing: Text(BmaDisplay.durationMinutes(item['credited_minutes'])),
            ),
          )),
      ];
    },
  );
}
