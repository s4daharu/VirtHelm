import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virthelm/core/models.dart';
import 'package:virthelm/ui/capacity_review_section.dart';

void main() {
  final snapshot = Inventory(
    nodes: const [Node(name: 'pve1', status: 'online', mem: 95, maxMem: 100)],
    guests: const [],
    fetchedAt: DateTime.utc(2026, 11, 19),
  );

  Widget display({
    required bool trusted,
    List<StoragePool> storages = const [],
  }) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: CapacityReviewSection(
          inventory: snapshot,
          storages: storages,
          isTrusted: trusted,
        ),
      ),
    ),
  );

  testWidgets('fresh trusted metrics show review evidence, not an action', (
    tester,
  ) async {
    await tester.pumpWidget(display(trusted: true));
    expect(find.byKey(const Key('capacity-review')), findsOneWidget);
    expect(find.textContaining('Node memory • pve1'), findsOneWidget);
    expect(find.textContaining('95.0% used in this snapshot'), findsOneWidget);
    expect(find.textContaining('No trend, forecast'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsNothing);
  });

  testWidgets('stale or incomplete input never produces apparent advice', (
    tester,
  ) async {
    await tester.pumpWidget(display(trusted: false));
    expect(find.textContaining('unavailable until a fresh'), findsOneWidget);
    expect(find.byKey(const Key('capacity-signal-0')), findsNothing);
  });

  testWidgets('missing measurements never imply all resources healthy', (
    tester,
  ) async {
    final missing = Inventory(
      nodes: const [Node(name: 'pve1', status: 'online')],
      guests: const [],
      fetchedAt: DateTime.utc(2026, 11, 19),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CapacityReviewSection(
            inventory: missing,
            storages: const [],
            isTrusted: true,
          ),
        ),
      ),
    );
    expect(
      find.textContaining('No usable capacity measurements'),
      findsOneWidget,
    );
    expect(find.textContaining('Missing metrics must not'), findsOneWidget);
  });
}
