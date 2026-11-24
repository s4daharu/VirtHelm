import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virthelm/core/models.dart';
import 'package:virthelm/ui/storage_history_review_card.dart';

void main() {
  final now = DateTime.utc(2026, 11, 24, 12);
  final series = StorageMetricSeries(
    points: List.generate(
      7,
      (i) => StorageMetricPoint(
        timestamp: now.subtract(Duration(hours: (6 - i) * 4)),
        usedBytes: 40 + i * 4,
        totalBytes: 100,
      ),
    ),
  );
  const storage = StoragePool(
    node: 'pve1',
    id: 'local',
    type: 'dir',
    active: true,
    used: 64,
    total: 100,
  );

  Widget display({
    required bool trusted,
    StoragePool? current = storage,
    StorageMetricTimeframe timeframe = StorageMetricTimeframe.day,
  }) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: StorageHistoryReviewCard(
          series: series,
          timeframe: timeframe,
          now: now,
          isTrusted: trusted,
          currentStorage: current,
        ),
      ),
    ),
  );

  testWidgets('shows an as-of scenario and its non-statistical caveat', (
    tester,
  ) async {
    await tester.pumpWidget(display(trusted: true));
    expect(find.byKey(const Key('storage-runway')), findsOneWidget);
    expect(find.textContaining('36–36 hours'), findsOneWidget);
    expect(find.textContaining('not a confidence interval'), findsOneWidget);
    expect(find.textContaining('if growth continues'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('does not estimate for untrusted or missing current storage', (
    tester,
  ) async {
    await tester.pumpWidget(display(trusted: false));
    expect(find.textContaining('36–36 hours'), findsNothing);
    await tester.pumpWidget(display(trusted: true, current: null));
    expect(find.textContaining('Runway scenario unavailable'), findsOneWidget);
    expect(find.textContaining('36–36 hours'), findsNothing);
  });

  testWidgets('short history cannot show a runway estimate', (tester) async {
    await tester.pumpWidget(
      display(trusted: true, timeframe: StorageMetricTimeframe.hour),
    );
    expect(find.textContaining('36–36 hours'), findsNothing);
  });
}
