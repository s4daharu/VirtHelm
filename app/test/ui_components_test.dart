import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
