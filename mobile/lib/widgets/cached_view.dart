import 'package:flutter/material.dart';

import '../core/api_client.dart';

class CachedView extends StatefulWidget {
  const CachedView({required this.load, required this.builder, super.key});

  final Future<CachedResponse> Function() load;
  final List<Widget> Function(BuildContext context, Map<String, dynamic> data) builder;

  @override
  State<CachedView> createState() => _CachedViewState();
}

class _CachedViewState extends State<CachedView> {
  late Future<CachedResponse> _future = widget.load();

  Future<void> _reload() async {
    setState(() => _future = widget.load());
    await _future;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<CachedResponse>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 42),
                const SizedBox(height: 12),
                Text('Chưa thể tải dữ liệu: ${snapshot.error}', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: _reload, child: const Text('Thử lại')),
              ],
            ),
          ),
        );
      }
      final response = snapshot.requireData;
      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          children: [
            if (response.isStale)
              const Card(
                color: Color(0xffffefd1),
                child: ListTile(
                  leading: Icon(Icons.offline_bolt_outlined),
                  title: Text('Đang xem dữ liệu đã lưu'),
                  subtitle: Text('Kết nối mạng hiện không khả dụng.'),
                ),
              ),
            ...widget.builder(context, response.data),
          ],
        ),
      );
    },
  );
}
