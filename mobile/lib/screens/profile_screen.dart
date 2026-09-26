import 'package:flutter/material.dart';

import '../core/bma_repository.dart';
import '../core/app_state.dart';
import '../core/api_client.dart';
import '../models/display.dart';
import '../widgets/cached_view.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({required this.repository, required this.state, super.key});

  final BmaRepository repository;
  final AppState state;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: Card(
          child: ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Đổi mật khẩu'),
            subtitle: const Text('Đăng nhập lại sau khi đổi.'),
            onTap: () => showDialog<void>(
              context: context,
              builder: (context) => _ChangePasswordDialog(repository: repository, state: state),
            ),
          ),
        ),
      ),
      Expanded(child: CachedView(
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
      )),
    ],
  );
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.repository, required this.state});
  final BmaRepository repository;
  final AppState state;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final current = TextEditingController();
  final next = TextEditingController();
  String? error;
  bool saving = false;

  @override
  void dispose() {
    current.dispose();
    next.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (next.text.length < 10 || next.text == current.text) {
      setState(() => error = 'Mật khẩu mới cần ít nhất 10 ký tự và khác mật khẩu cũ.');
      return;
    }
    setState(() { saving = true; error = null; });
    try {
      await widget.repository.changePassword(current.text, next.text);
      if (mounted) Navigator.pop(context);
      await widget.state.logoutAfterPasswordChange();
    } on ApiException {
      if (mounted) setState(() => error = 'Không đổi được mật khẩu. Kiểm tra mật khẩu cũ và kết nối.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Đổi mật khẩu'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(controller: current, obscureText: true, decoration: const InputDecoration(labelText: 'Mật khẩu hiện tại')),
        TextField(controller: next, obscureText: true, decoration: const InputDecoration(labelText: 'Mật khẩu mới (ít nhất 10 ký tự)')),
        if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ],
    ),
    actions: [
      TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('Hủy')),
      FilledButton(onPressed: saving ? null : submit, child: const Text('Lưu')),
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
