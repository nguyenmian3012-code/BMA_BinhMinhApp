import 'package:bma/widgets/sparkline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('sparkline renders without a chart dependency', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Sparkline(values: [90, 91, 93, 92], color: Colors.red)),
      ),
    );
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
