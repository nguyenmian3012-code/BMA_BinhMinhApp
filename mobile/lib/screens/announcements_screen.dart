import 'package:flutter/material.dart';

import '../core/bma_repository.dart';
import '../models/display.dart';
import '../widgets/cached_view.dart';

class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({required this.repository, super.key});

  final BmaRepository repository;

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  final Set<String> _locallyRead = {};

  @override
  Widget build(BuildContext context) => CachedView(
    load: widget.repository.announcements,
    builder: (context, data) {
      final items = (data['items'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      if (items.isEmpty) {
        return const [Card(child: ListTile(title: Text('Chưa có thông báo.')))];
      }
      return items.map((item) {
        final id = item['id']?.toString() ?? '';
        final unread = item['read_at'] == null && !_locallyRead.contains(id);
        return Card(
          color: unread ? const Color(0xfffff6f4) : null,
          child: ListTile(
            leading: Icon(
              item['priority'] == 'EMERGENCY'
                  ? Icons.warning_amber
                  : Icons.campaign_outlined,
            ),
            title: Text(
              item['title']?.toString() ?? '',
              style: TextStyle(
                fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            subtitle: Text(
              '${item['body'] ?? ''}\n${BmaDisplay.dateTime(item['published_at'])}',
            ),
            trailing: Chip(
              label: Text(unread ? 'Chưa đọc' : 'Đã đọc'),
            ),
            isThreeLine: true,
            onTap: unread ? () => _markRead(id) : null,
          ),
        );
      }).toList();
    },
  );

  Future<void> _markRead(String id) async {
    setState(() => _locallyRead.add(id));
    try {
      await widget.repository.markAnnouncementRead(id);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Đã lưu trạng thái trên thiết bị nhưng chưa thể đồng bộ máy chủ.',
          ),
        ),
      );
    }
  }
}
