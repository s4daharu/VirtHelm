import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:virthelm/core/app_controller.dart';
import 'package:virthelm/core/models.dart';
import 'package:virthelm/core/profile_repository.dart';
import 'package:virthelm/ui/node_page.dart';

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
  final reads = <String>[];
  Completer<NodeMetricSeries?>? pending;

  NodeMetricSeries history(String name) => NodeMetricSeries(
    points: List.generate(
      7,
      (i) => NodeMetricPoint(
        timestamp: now.subtract(Duration(minutes: (6 - i) * 10)),
        cpuFraction: name == 'pve1' ? 0.2 : 0.8,
        memoryFraction: name == 'pve1' ? 0.4 : 0.6,
      ),
    ),
  );

  @override
  Future<NodeMetricSeries?> inspectNodeMetrics({
    required String profileId,
    required int generation,
    required Node node,
    required NodeMetricTimeframe timeframe,
  }) async {
    reads.add(node.name);
    if (node.name == 'pve2' && pending != null) return pending!.future;
    return history(node.name);
  }
}

void main() {
  const primary = Node(name: 'pve1', status: 'online');
  const peer = Node(name: 'pve2', status: 'online');

  Future<_Controller> open(WidgetTester tester, {bool duplicate = false}) async {
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
      nodes: [primary, peer, if (duplicate) peer],
      guests: const [],
      fetchedAt: DateTime.now(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: NodePage(
          controller: controller,
          node: primary,
          profileId: 'a',
          generation: controller.connectionGeneration,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('node-metrics-tab')));
    await tester.pumpAndSettle();
    expect(controller.reads, isEmpty);
    await tester.tap(find.text('Load history'));
    await tester.pumpAndSettle();
    expect(controller.reads, ['pve1']);
    return controller;
  }

  Future<void> selectPeer(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('node-comparison-peer')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('pve2').last);
    await tester.pumpAndSettle();
  }

  testWidgets('peer read is explicit and timeframe change clears results', (
    tester,
  ) async {
    final controller = await open(tester);
    await selectPeer(tester);
    expect(controller.reads, ['pve1']);
    await tester.tap(find.byKey(const Key('load-node-comparison')));
    await tester.pumpAndSettle();
    expect(controller.reads, ['pve1', 'pve2']);
    expect(find.text('7 matched RRD samples'), findsOneWidget);
    expect(find.text('pve2: CPU 80.0%, memory 60.0%'), findsOneWidget);
    await tester.tap(find.text('24 hours'));
    await tester.pumpAndSettle();
    expect(find.text('7 matched RRD samples'), findsNothing);
    expect(controller.reads, ['pve1', 'pve2']);
  });

  testWidgets('ambiguous peer cannot be selected or fetched', (tester) async {
    final controller = await open(tester, duplicate: true);
    expect(find.byKey(const Key('node-comparison-peer')), findsNothing);
    expect(controller.reads, ['pve1']);
  });

  testWidgets('profile switch redacts a delayed peer response', (tester) async {
    final controller = await open(tester);
    await selectPeer(tester);
    controller.pending = Completer<NodeMetricSeries?>();
    await tester.tap(find.byKey(const Key('load-node-comparison')));
    await tester.pump();
    expect(controller.reads, ['pve1', 'pve2']);
    controller.active = const ConnectionProfile(
      id: 'b',
      name: 'B',
      endpoint: 'https://b.example',
    );
    controller.notifyListeners();
    controller.pending!.complete(controller.history('pve2'));
    await tester.pumpAndSettle();
    expect(find.text('Node unavailable'), findsOneWidget);
    expect(find.text('7 matched RRD samples'), findsNothing);
    expect(find.textContaining('pve2: CPU'), findsNothing);
  });
}
