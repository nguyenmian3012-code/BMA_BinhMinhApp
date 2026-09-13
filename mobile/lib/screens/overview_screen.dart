import 'package:flutter/material.dart';

import '../core/bma_repository.dart';
import '../models/display.dart';
import '../widgets/cached_view.dart';

class OverviewScreen extends StatelessWidget {
  const OverviewScreen({required this.repository, super.key});

  final BmaRepository repository;

  @override
  Widget build(BuildContext context) => CachedView(
    load: repository.dashboard,
    builder: (context, data) {
      final state = data['plant_state'];
      final unknown = state == 'UNKNOWN';
      return [
        Card(
          color: unknown ? const Color(0xffffefd1) : const Color(0xfffffafa),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('TRẠNG THÁI NHÀ MÁY'),
                const SizedBox(height: 8),
                Text(
                  BmaDisplay.plantState(state),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: unknown ? Colors.orange.shade900 : const Color(0xff8f151b),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (unknown) const Text('Heartbeat thiếu hoặc đã cũ; BMA không tự kết luận nhà máy dừng.'),
                if (data['running_since'] != null)
                  Text('Bắt đầu: ${BmaDisplay.dateTime(data['running_since'])}'),
              ],
            ),
          ),
        ),
        _SectionTitle('Giờ hoạt động tháng này'),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _HourCard('Tổng', data['month_operating_hours'], Icons.timelapse),
            _HourCard('Cao điểm', data['peak_hours'], Icons.trending_up),
            _HourCard('Bình thường', data['normal_hours'], Icons.schedule),
            _HourCard('Thấp điểm', data['off_peak_hours'], Icons.nightlight_outlined),
          ],
        ),
        const SizedBox(height: 8),
        Text('Quy tắc: ${data['time_of_use_rule_version'] ?? 'Chưa cấu hình'}', style: Theme.of(context).textTheme.bodySmall),
        _SectionTitle('Kế hoạch tiếp theo'),
        Card(
          child: ListTile(
            leading: const Icon(Icons.event_available_outlined),
            title: Text(data['next_planned_start'] == null
                ? 'Chưa có lịch được xác nhận'
                : BmaDisplay.dateTime(data['next_planned_start'])),
            subtitle: const Text('Lịch được Admin quản lý và có trạng thái planned/confirmed.'),
          ),
        ),
        _RecoveryCard(repository: repository),
      ];
    },
  );
}

class _RecoveryCard extends StatelessWidget {
  const _RecoveryCard({required this.repository});

  final BmaRepository repository;

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: repository.recovery(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) return const SizedBox.shrink();
      final data = snapshot.requireData.data;
      final available = data['status'] == 'AVAILABLE';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle('Tỷ lệ thu hồi'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.percent),
              title: Text(available
                  ? BmaDisplay.number(data['value_percent'], digits: 2, unit: '%')
                  : 'Chưa đủ dữ liệu'),
              subtitle: Text(available
                  ? 'Kỳ ${data['period_id']} · ${data['basis']} · ${data['formula_version']}'
                  : 'Cần đủ khối lượng khoai đầu vào và tinh bột đầu ra cùng kỳ/basis.'),
            ),
          ),
        ],
      );
    },
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
  );
}

class _HourCard extends StatelessWidget {
  const _HourCard(this.label, this.value, this.icon);
  final String label;
  final Object? value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 154,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xff8f151b)),
            const SizedBox(height: 8),
            Text(BmaDisplay.number(value, digits: 2, unit: ' giờ'), style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(label),
          ],
        ),
      ),
    ),
  );
}
