import 'dart:async';

import 'package:bma/core/api_client.dart';
import 'package:bma/widgets/cached_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('cached view shows loading state', (tester) async {
    final pending = Completer<CachedResponse>();
    addTearDown(() {
      if (!pending.isCompleted) {
        pending.complete(
          const CachedResponse({}, isStale: false, fromCache: false),
        );
      }
    });

    await tester.pumpWidget(
      MaterialApp(
        home: CachedView(
          load: () => pending.future,
          builder: (_, _) => const [Text('Loaded')],
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Loaded'), findsNothing);
  });

  testWidgets('cached view shows recoverable error state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CachedView(
          load: () => Future<CachedResponse>.error(
            const ApiException('NETWORK_UNAVAILABLE'),
          ),
          builder: (_, _) => const [Text('Loaded')],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('NETWORK_UNAVAILABLE'), findsOneWidget);
    expect(find.text('Thử lại'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
  });
}
