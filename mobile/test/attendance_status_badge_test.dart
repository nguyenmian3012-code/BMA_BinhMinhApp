import 'package:bma/screens/attendance_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('needs-review status has visible and semantic warning', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AttendanceStatusBadge(
            status: 'NEEDS_REVIEW',
            reviewReason: 'MISSING_ENTRY',
          ),
        ),
      ),
    );

    expect(find.text('Thiếu giờ vào · tạm tính 50%'), findsOneWidget);
    expect(find.byIcon(Icons.report_problem_outlined), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Cần kiểm tra: Thiếu giờ vào · tạm tính 50%',
      ),
      findsOneWidget,
    );
  });
}
