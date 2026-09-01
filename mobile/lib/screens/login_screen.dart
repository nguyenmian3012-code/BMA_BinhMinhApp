import 'package:flutter/material.dart';

import '../core/app_state.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({required this.state, super.key});

  final AppState state;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(26),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _BmaMark(),
                      const SizedBox(height: 18),
                      Text('Bình Minh App', style: Theme.of(context).textTheme.headlineMedium, textAlign: TextAlign.center),
                      const Text('Thông tin nhà máy và nhân viên', textAlign: TextAlign.center),
                      const SizedBox(height: 28),
                      TextFormField(
                        controller: _username,
                        decoration: const InputDecoration(labelText: 'Tên đăng nhập', prefixIcon: Icon(Icons.person_outline)),
                        autofillHints: const [AutofillHints.username],
                        validator: (value) => (value?.trim().length ?? 0) < 3 ? 'Nhập ít nhất 3 ký tự.' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _password,
                        decoration: const InputDecoration(labelText: 'Mật khẩu', prefixIcon: Icon(Icons.lock_outline)),
                        obscureText: true,
                        autofillHints: const [AutofillHints.password],
                        validator: (value) => (value?.length ?? 0) < 10 ? 'Mật khẩu có ít nhất 10 ký tự.' : null,
                      ),
                      if (widget.state.message != null) ...[
                        const SizedBox(height: 12),
                        Text(widget.state.message!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: widget.state.loading ? null : _login,
                        child: widget.state.loading
                            ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Đăng nhập'),
                      ),
                      TextButton(
                        onPressed: widget.state.loading ? null : _register,
                        child: const Text('Tạo tài khoản mới'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    await widget.state.login(_username.text, _password.text);
  }

  Future<void> _register() async {
    await showDialog<void>(
      context: context,
      builder: (context) => RegisterDialog(state: widget.state),
    );
  }
}

class RegisterDialog extends StatefulWidget {
  const RegisterDialog({required this.state, super.key});

  final AppState state;

  @override
  State<RegisterDialog> createState() => _RegisterDialogState();
}

class _RegisterDialogState extends State<RegisterDialog> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _employee = TextEditingController();

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _name.dispose();
    _employee.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Tạo tài khoản'),
    content: SizedBox(
      width: 420,
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Họ tên'), validator: _required),
              TextFormField(controller: _employee, decoration: const InputDecoration(labelText: 'Mã nhân viên (nếu có)')),
              TextFormField(controller: _username, decoration: const InputDecoration(labelText: 'Tên đăng nhập'), validator: _required),
              TextFormField(controller: _password, decoration: const InputDecoration(labelText: 'Mật khẩu'), obscureText: true, validator: (value) => (value?.length ?? 0) < 10 ? 'Ít nhất 10 ký tự.' : null),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
      FilledButton(onPressed: _submit, child: const Text('Đăng ký')),
    ],
  );

  String? _required(String? value) => (value?.trim().isEmpty ?? true) ? 'Không được bỏ trống.' : null;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final success = await widget.state.register(
      username: _username.text,
      password: _password.text,
      displayName: _name.text,
      employeeCode: _employee.text.isEmpty ? null : _employee.text,
    );
    if (success && mounted) Navigator.pop(context);
  }
}

class _BmaMark extends StatelessWidget {
  const _BmaMark();

  @override
  Widget build(BuildContext context) => Center(
    child: Image.asset(
      'assets/brand/bm7-app-icon.png',
      width: 88,
      height: 88,
      filterQuality: FilterQuality.high,
      semanticLabel: 'Logo Bình Minh',
    ),
  );
}
