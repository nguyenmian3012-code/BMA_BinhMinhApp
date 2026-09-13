import 'package:flutter/material.dart';

import '../core/bma_repository.dart';
import '../models/display.dart';
import '../widgets/cached_view.dart';

class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({
    required this.repository,
    this.onUnreadCountChanged,
    super.key,
  });

  final BmaRepository repository;
  final ValueChanged<int>? onUnreadCountChanged;

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
      _reportUnreadCount(items);
      if (items.isEmpty) {
        return const [Card(child: ListTile(title: Text('Chưa có thông báo.')))];
      }
      return items.map((item) {
        final id = item['id']?.toString() ?? '';
        final unread = item['read_at'] == null && !_locallyRead.contains(id);
        return Card(
          color: unread ? const Color(0xffffded9) : const Color(0xfffffbfa),
          child: ListTile(
            leading: Icon(
              item['priority'] == 'EMERGENCY'
                  ? Icons.warning_amber
                  : Icons.campaign_outlined,
              color: unread ? const Color(0xff941820) : null,
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
              backgroundColor: unread
                  ? const Color(0xff941820)
                  : const Color(0xffeee7e3),
              label: Text(
                unread ? 'Chưa đọc' : 'Đã đọc',
                style: TextStyle(
                  color: unread ? Colors.white : const Color(0xff5f5551),
                ),
              ),
            ),
            isThreeLine: true,
            onTap: unread ? () => _markRead(id) : null,
          ),
        );
      }).toList();
    },
  );

  void _reportUnreadCount(List<Map<String, dynamic>> items) {
    final count = items.where((item) {
      final id = item['id']?.toString() ?? '';
      return item['read_at'] == null && !_locallyRead.contains(id);
    }).length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onUnreadCountChanged?.call(count);
    });
  }

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
