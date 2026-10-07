import 'package:bma/screens/attendance_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('missing entry has visible and semantic warning', (tester) async {
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

  testWidgets('missing exit keeps its Vietnamese explanation', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AttendanceStatusBadge(
            status: 'NEEDS_REVIEW',
            reviewReason: 'MISSING_EXIT',
          ),
        ),
      ),
    );

    expect(find.text('Thiếu giờ ra · tạm tính 50%'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Cần kiểm tra: Thiếu giờ ra · tạm tính 50%'),
      findsOneWidget,
    );
  });

  testWidgets('attendance content has an explicit empty state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AttendanceContent(
            data: {
              'month': '2026-09',
              'shift_name': 'Ca Hành Chính',
              'monthly_total_minutes': 0,
              'items': [],
            },
          ),
        ),
      ),
    );

    expect(find.text('Chưa có dữ liệu chấm công.'), findsOneWidget);
  });

  testWidgets('attendance shows presence and late duration', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AttendanceContent(
              data: {
                'presence_status': 'INSHIFT',
                'month': '2026-10',
                'monthly_total_minutes': 0,
                'items': [
                  {
                    'work_date': '2026-10-06',
                    'entry_at': '2026-10-06T07:45:00+07:00',
                    'exit_at': null,
                    'credited_minutes': 0,
                    'status': 'PROVISIONAL',
                    'late_minutes': 45,
                    'late_duration': '00:45',
                  },
                ],
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('Đang trong ca'), findsOneWidget);
    expect(find.text('Đi trễ: 00:45'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Đang trong ca')), findsWidgets);
  });

  testWidgets('attendance content supports 1.3 text scale', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 800),
            textScaler: TextScaler.linear(1.3),
          ),
          child: const Scaffold(
            body: SingleChildScrollView(
              child: AttendanceContent(
                data: {
                  'month': '2026-09',
                  'shift_name': 'Ca Hành Chính',
                  'monthly_total_minutes': 240,
                  'items': [
                    {
                      'work_date': '2026-09-30',
                      'entry_at': null,
                      'exit_at': '2026-09-30T13:01:06.835+07:00',
                      'credited_minutes': 240,
                      'status': 'NEEDS_REVIEW',
                      'review_reason': 'MISSING_ENTRY',
                    },
                  ],
                },
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Thiếu giờ vào · tạm tính 50%'), findsOneWidget);
  });
}
