import 'package:flutter/material.dart';

import '../core/bma_repository.dart';
import '../models/display.dart';
import '../widgets/cached_view.dart';

class AnnouncementsScreen extends StatelessWidget {
  const AnnouncementsScreen({required this.repository, super.key});

  final BmaRepository repository;

  @override
  Widget build(BuildContext context) => CachedView(
    load: repository.announcements,
    builder: (context, data) {
      final items = (data['items'] as List? ?? const []).whereType<Map<String, dynamic>>().toList();
      if (items.isEmpty) return const [Card(child: ListTile(title: Text('Chưa có thông báo.')))];
      return items.map((item) {
        final unread = item['read_at'] == null;
        return Card(
          color: unread ? const Color(0xfffff6f4) : null,
          child: ListTile(
            leading: Icon(item['priority'] == 'EMERGENCY' ? Icons.warning_amber : Icons.campaign_outlined),
            title: Text(item['title']?.toString() ?? '', style: TextStyle(fontWeight: unread ? FontWeight.w700 : FontWeight.w500)),
            subtitle: Text('${item['body'] ?? ''}\n${BmaDisplay.dateTime(item['published_at'])}'),
            isThreeLine: true,
            onTap: unread ? () => repository.markAnnouncementRead(item['id'].toString()) : null,
          ),
        );
      }).toList();
    },
  );
}
