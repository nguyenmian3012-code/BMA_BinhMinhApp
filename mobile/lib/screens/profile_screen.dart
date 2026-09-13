import 'package:flutter/material.dart';

import '../core/bma_repository.dart';
import '../models/display.dart';
import '../widgets/cached_view.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({required this.repository, super.key});

  final BmaRepository repository;

  @override
  Widget build(BuildContext context) => CachedView(
    load: repository.profile,
    builder: (context, data) => [
      Card(
        child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person)),
          title: Text(data['full_name']?.toString() ?? 'Chưa liên kết hồ sơ'),
          subtitle: Text('${data['employee_code'] ?? ''} · ${data['department'] ?? ''} · ${data['position'] ?? ''}'),
        ),
      ),
      _ProfileSection('Trách nhiệm', data['responsibilities']),
      _ProfileSection('Nghĩa vụ', data['obligations']),
      _ProfileSection('Quyền lợi', data['benefits']),
      _ProfileSection('Trọng trách', data['accountabilities']),
      Card(
        child: ListTile(
          title: Text('Phiên bản ${data['version'] ?? '-'}'),
          subtitle: Text('Hiệu lực ${data['effective_from'] ?? '-'} · cập nhật ${BmaDisplay.dateTime(data['updated_at'])}'),
        ),
      ),
    ],
  );
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection(this.title, this.value);
  final String title;
  final Object? value;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(value?.toString().trim().isNotEmpty == true ? value.toString() : 'Chưa cập nhật'),
        ],
      ),
    ),
  );
}
