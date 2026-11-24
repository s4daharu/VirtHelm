import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virthelm/core/models.dart';
import 'package:virthelm/ui/storage_history_review_card.dart';

void main() {
  final now = DateTime.utc(2026, 11, 24, 12);
  final series = StorageMetricSeries(
    points: List.generate(
      5,
      (i) => StorageMetricPoint(
        timestamp: now.subtract(Duration(minutes: (4 - i) * 10)),
        usedBytes: 40 + i * 5,
        totalBytes: 100,
      ),
    ),
  );

  Widget display({required bool trusted, StorageMetricSeries? history}) =>
      MaterialApp(
        home: Scaffold(
          body: StorageHistoryReviewCard(
            series: history ?? series,
            timeframe: StorageMetricTimeframe.hour,
            now: now,
            isTrusted: trusted,
          ),
        ),
      );

  testWidgets('shows evidence and explicitly disclaims prediction', (
    tester,
  ) async {
    await tester.pumpWidget(display(trusted: true));
    expect(find.text('Observed capacity change'), findsOneWidget);
    expect(find.textContaining('20.00 percentage points'), findsOneWidget);
    expect(find.textContaining('5 RRD averages'), findsOneWidget);
    expect(find.textContaining('Not a continuous trend'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('untrusted or incomplete history never shows comparison', (
    tester,
  ) async {
    await tester.pumpWidget(display(trusted: false));
    expect(find.textContaining('Comparison unavailable'), findsOneWidget);
    expect(find.textContaining('percentage points'), findsNothing);
    await tester.pumpWidget(
      display(
        trusted: true,
        history: StorageMetricSeries(points: series.points, truncated: true),
      ),
    );
    expect(find.textContaining('Comparison unavailable'), findsOneWidget);
    expect(find.textContaining('percentage points'), findsNothing);
  });
}
