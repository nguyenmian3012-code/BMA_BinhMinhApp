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
              BmaDisplay.compactDurationMinutes(data['monthly_total_minutes']),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
        if (items.isEmpty)
          const Card(child: ListTile(title: Text('Chưa có dữ liệu chấm công.')))
        else
          ...items.map((item) => Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      item['status'] == 'NEEDS_REVIEW'
                          ? Icons.report_problem_outlined
                          : Icons.access_time,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          BmaDisplay.date(item['work_date']),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${BmaDisplay.time(item['entry_at'])} → '
                                '${BmaDisplay.time(item['exit_at'])}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              BmaDisplay.compactDurationMinutes(
                                item['credited_minutes'],
                              ),
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(BmaDisplay.attendanceStatus(
                          item['status'],
                          item['review_reason'],
                        )),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )),
      ];
    },
  );
}
