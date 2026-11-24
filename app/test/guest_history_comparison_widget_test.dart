import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:virthelm/core/app_controller.dart';
import 'package:virthelm/core/models.dart';
import 'package:virthelm/core/profile_repository.dart';
import 'package:virthelm/ui/guest_page.dart';

class _Vault implements CredentialVault {
  @override
  Future<void> store(String id, ApiCredentials credentials) async {}
  @override
  Future<ApiCredentials?> retrieve(String id) async => null;
  @override
  Future<void> remove(String id) async {}
}

class _Controller extends AppController {
  _Controller(ProfileRepository repository) : super(repository: repository);

  final now = DateTime.now();
  final reads = <int>[];
  final readNodes = <String>[];
  Completer<GuestMetricSeries?>? pending;

  GuestMetricSeries history(int vmid) => GuestMetricSeries(
    points: List.generate(
      7,
      (i) => GuestMetricPoint(
        timestamp: now.subtract(Duration(minutes: (6 - i) * 10)),
        cpuFraction: vmid == 101 ? 0.2 : 0.8,
        memoryFraction: vmid == 101 ? 0.4 : 0.6,
      ),
    ),
  );

  @override
  Future<GuestMetricSeries?> inspectGuestMetrics({
    required String profileId,
    required int generation,
    required Guest guest,
    required GuestMetricTimeframe timeframe,
  }) async {
    reads.add(guest.vmid);
    readNodes.add(guest.node);
    if (guest.vmid == 102 && pending != null) return pending!.future;
    return history(guest.vmid);
  }
}

void main() {
  const primary = Guest(
    node: 'pve1',
    vmid: 101,
    kind: 'qemu',
    name: 'Primary',
    status: 'running',
  );
  const peer = Guest(
    node: 'pve1',
    vmid: 102,
    kind: 'qemu',
    name: 'Peer',
    status: 'running',
  );

  const remote = Guest(
    node: 'pve2',
    vmid: 102,
    kind: 'qemu',
    name: 'Peer',
    status: 'running',
  );

  Future<_Controller> open(
    WidgetTester tester, {
    bool duplicate = false,
    bool crossNode = false,
  }) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = _Controller(ProfileRepository(prefs, _Vault()));
    addTearDown(controller.dispose);
    controller.active = const ConnectionProfile(
      id: 'a',
      name: 'A',
      endpoint: 'https://a.example',
    );
    controller.inventory = Inventory(
      nodes: [
        const Node(name: 'pve1', status: 'online'),
        if (crossNode) const Node(name: 'pve2', status: 'online'),
      ],
      guests: [primary, crossNode ? remote : peer, if (duplicate) peer],
      fetchedAt: DateTime.now(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: GuestPage(
          controller: controller,
          guest: primary,
          profileId: 'a',
          generation: controller.connectionGeneration,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('guest-metrics-tab')));
    await tester.tap(find.byKey(const Key('guest-metrics-tab')));
    await tester.pumpAndSettle();
    expect(controller.reads, isEmpty);
    await tester.tap(find.text('Load history'));
    await tester.pumpAndSettle();
    expect(controller.reads, [101]);
    return controller;
  }

  Future<void> selectPeer(
    WidgetTester tester, {
    String label = '102 · Peer',
  }) async {
    await tester.tap(find.byKey(const Key('guest-comparison-peer')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('peer read is explicit and timeframe change clears results', (
    tester,
  ) async {
    final controller = await open(tester);
    await selectPeer(tester);
    expect(controller.reads, [101]);
    await tester.tap(find.byKey(const Key('load-guest-comparison')));
    await tester.pumpAndSettle();
    expect(controller.reads, [101, 102]);
    expect(find.text('7 matched RRD samples'), findsOneWidget);
    expect(find.text('VMID 102: CPU 80.0%, memory 60.0%'), findsOneWidget);
    await tester.tap(find.text('24 hours'));
    await tester.pumpAndSettle();
    expect(find.text('7 matched RRD samples'), findsNothing);
    expect(controller.reads, [101, 102]);
  });

  testWidgets('ambiguous peer cannot be selected or fetched', (tester) async {
    final controller = await open(tester, duplicate: true);
    expect(find.byKey(const Key('guest-comparison-peer')), findsNothing);
    expect(controller.reads, [101]);
  });

  testWidgets('inventory refresh invalidates completed and delayed results', (
    tester,
  ) async {
    final controller = await open(tester);
    await selectPeer(tester);
    await tester.tap(find.byKey(const Key('load-guest-comparison')));
    await tester.pumpAndSettle();
    expect(find.text('7 matched RRD samples'), findsOneWidget);
    controller.inventory = Inventory(
      nodes: const [Node(name: 'pve1', status: 'online')],
      guests: const [primary, peer],
      fetchedAt: DateTime.now(),
    );
    controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('7 matched RRD samples'), findsNothing);
    expect(controller.reads, [101, 102]);
    controller.pending = Completer<GuestMetricSeries?>();
    await tester.tap(find.byKey(const Key('load-guest-comparison')));
    await tester.pump();
    expect(controller.reads, [101, 102, 102]);
    controller.inventory = Inventory(
      nodes: const [Node(name: 'pve1', status: 'online')],
      guests: const [primary, peer],
      fetchedAt: DateTime.now(),
    );
    controller.notifyListeners();
    controller.pending!.complete(controller.history(102));
    await tester.pumpAndSettle();
    expect(find.text('7 matched RRD samples'), findsNothing);
    expect(
      find.text('Comparison unavailable. Refresh and try again.'),
      findsOneWidget,
    );
  });

  testWidgets('profile switch redacts a delayed peer response', (tester) async {
    final controller = await open(tester);
    await selectPeer(tester);
    controller.pending = Completer<GuestMetricSeries?>();
    await tester.tap(find.byKey(const Key('load-guest-comparison')));
    await tester.pump();
    expect(controller.reads, [101, 102]);
    controller.active = const ConnectionProfile(
      id: 'b',
      name: 'B',
      endpoint: 'https://b.example',
    );
    controller.notifyListeners();
    controller.pending!.complete(controller.history(102));
    await tester.pumpAndSettle();
    expect(find.text('Guest unavailable'), findsOneWidget);
    expect(find.text('7 matched RRD samples'), findsNothing);
    expect(find.textContaining('VMID 102: CPU'), findsNothing);
  });

  testWidgets('remote peer read is explicit and identifies both nodes', (
    tester,
  ) async {
    final controller = await open(tester, crossNode: true);
    await selectPeer(tester, label: '102 · Peer · pve2');
    expect(controller.readNodes, ['pve1']);
    await tester.tap(find.byKey(const Key('load-guest-comparison')));
    await tester.pumpAndSettle();
    expect(controller.readNodes, ['pve1', 'pve2']);
    expect(find.text('7 matched RRD samples'), findsOneWidget);
    expect(find.text('Nodes: pve1 / pve2'), findsOneWidget);
  });

  testWidgets('moved peer requires reselection before another GET', (
    tester,
  ) async {
    final controller = await open(tester, crossNode: true);
    await selectPeer(tester, label: '102 · Peer · pve2');
    controller.inventory = Inventory(
      nodes: const [
        Node(name: 'pve1', status: 'online'),
        Node(name: 'pve2', status: 'online'),
      ],
      guests: const [primary, peer],
      fetchedAt: DateTime.now(),
    );
    controller.notifyListeners();
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('load-guest-comparison')),
    );
    expect(button.onPressed, isNull);
    expect(controller.readNodes, ['pve1']);
    await selectPeer(tester);
    await tester.tap(find.byKey(const Key('load-guest-comparison')));
    await tester.pumpAndSettle();
    expect(controller.readNodes, ['pve1', 'pve1']);
    expect(find.text('7 matched RRD samples'), findsOneWidget);
  });
}
