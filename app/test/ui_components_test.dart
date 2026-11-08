import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virthelm/ui/components.dart';
import 'package:virthelm/ui/theme.dart';

void main() {
  testWidgets('status chips pair color with an icon and spoken label', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: virthelmTheme(Brightness.light),
        home: const Scaffold(
          body: Column(
            children: [
              StatusChip(status: 'running'),
              StatusChip(status: 'failed'),
              StatusChip(status: 'unknown'),
            ],
          ),
        ),
      ),
    );

    expect(find.text('running'), findsOneWidget);
    expect(find.text('failed'), findsOneWidget);
    expect(find.text('unknown'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.byIcon(Icons.error_rounded), findsOneWidget);
    expect(find.byIcon(Icons.help_outline_rounded), findsOneWidget);
    expect(find.bySemanticsLabel('Status: running'), findsOneWidget);
    expect(find.bySemanticsLabel('Status: failed'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('empty states expose an optional recovery action', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: virthelmTheme(Brightness.light),
        home: Scaffold(
          body: EmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Not connected',
            body: 'Refresh or verify the connection.',
            action: FilledButton(
              onPressed: () => tapped = true,
              child: const Text('Retry'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Not connected'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(tapped, isTrue);
  });

  test('AMOLED and high-contrast themes use explicit surface treatment', () {
    final amoled = virthelmTheme(Brightness.dark, amoled: true);
    expect(amoled.scaffoldBackgroundColor, Colors.black);

    final highContrast = virthelmTheme(
      Brightness.light,
      highContrast: true,
    );
    final cardShape = highContrast.cardTheme.shape as RoundedRectangleBorder;
    expect(cardShape.side.color, highContrast.colorScheme.outline);
  });

  testWidgets('sparklines expose axes and an accessible data table', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: virthelmTheme(Brightness.light),
        home: Scaffold(
          body: SparklineCard(
            title: 'CPU average',
            icon: Icons.memory_rounded,
            values: const [0.25, 0.5],
            timestamps: [
              DateTime.utc(2026, 11, 8, 10),
              DateTime.utc(2026, 11, 8, 11),
            ],
            summary: 'Latest 50.0%',
            axisLabel: 'CPU usage (%)',
            timeframeLabel: '1 hour',
          ),
        ),
      ),
    );

    expect(find.text('100%'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('CPU usage (%)'), findsOneWidget);
    expect(find.text('Time • 1 hour'), findsOneWidget);
    await tester.tap(find.text('View data table'));
    await tester.pumpAndSettle();
    expect(find.text('CPU average data'), findsOneWidget);
    expect(find.textContaining('UTC'), findsNWidgets(2));
  });

}
