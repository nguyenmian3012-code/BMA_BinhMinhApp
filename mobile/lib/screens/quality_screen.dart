import 'package:flutter/material.dart';

import '../core/bma_repository.dart';
import '../models/display.dart';
import '../widgets/cached_view.dart';
import '../widgets/sparkline.dart';

class QualityScreen extends StatelessWidget {
  const QualityScreen({required this.repository, super.key});

  final BmaRepository repository;

  @override
  Widget build(BuildContext context) => CachedView(
    load: repository.quality,
    builder: (context, data) {
      final items = (data['items'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      if (items.isEmpty) {
        return const [Card(child: ListTile(title: Text('Chưa có kết quả BMKCS đã Publish.')))];
      }
      final latest = items.first;
      return [
        Card(
          child: ListTile(
            leading: const Icon(Icons.science),
            title: Text('Lot ${latest['lot_code']}'),
            subtitle: Text('${BmaDisplay.dateTime(latest['measured_at'])} · ${latest['freshness']}'),
          ),
        ),
        const SizedBox(height: 10),
        _Metric(
          title: 'Độ trắng',
          value: latest['whiteness'],
          unit: '%',
          values: _values(items, 'whiteness'),
          color: const Color(0xff8f151b),
        ),
        _Metric(
          title: 'Độ ẩm',
          value: latest['moisture'],
          unit: '%',
          values: _values(items, 'moisture'),
          color: Colors.blue.shade700,
        ),
        _Metric(
          title: 'Độ pH',
          value: latest['ph'],
          unit: '',
          values: _values(items, 'ph'),
          color: Colors.green.shade700,
        ),
        _Metric(
          title: 'Độ mịn',
          value: latest['fineness'],
          unit: latest['fineness_unit']?.toString() ?? '',
          values: _values(items, 'fineness'),
          color: Colors.deepPurple.shade600,
          note: latest['fineness'] == null
              ? 'BMKCS hiện chưa phát field độ mịn riêng. BMA không dùng viscosity/extra_value thay thế.'
              : null,
        ),
      ];
    },
  );

  static List<double> _values(List<Map<String, dynamic>> items, String key) => items
      .map((item) => item[key])
      .whereType<num>()
      .map((value) => value.toDouble())
      .toList()
      .reversed
      .toList();
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.title,
    required this.value,
    required this.unit,
    required this.values,
    required this.color,
    this.note,
  });

  final String title;
  final Object? value;
  final String unit;
  final List<double> values;
  final Color color;
  final String? note;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              Text(BmaDisplay.number(value, digits: 2, unit: unit), style: TextStyle(fontSize: 20, color: color, fontWeight: FontWeight.w700)),
            ],
          ),
          if (values.length > 1) Sparkline(values: values, color: color),
          if (note != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(note!, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    ),
  );
}
