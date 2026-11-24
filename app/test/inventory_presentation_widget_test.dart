import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:virthelm/core/app_controller.dart';
import 'package:virthelm/core/device_connectivity.dart';
import 'package:virthelm/core/models.dart';
import 'package:virthelm/core/profile_repository.dart';
import 'package:virthelm/ui/guest_page.dart';
import 'package:virthelm/ui/node_page.dart';
import 'package:virthelm/ui/shell.dart';
import 'package:virthelm/ui/storage_page.dart';
import 'package:virthelm/ui/theme.dart';

class _Vault implements CredentialVault {
  @override
  Future<void> store(String id, ApiCredentials credentials) async {}
  @override
  Future<ApiCredentials?> retrieve(String id) async => null;
  @override
  Future<void> remove(String id) async {}
}

const _guest = Guest(
  node: 'lab-node',
  vmid: 101,
  kind: 'qemu',
  name: 'Sample guest',
  status: 'running',
);
const _node = Node(name: 'lab-node', status: 'online', cpu: 0.2);
const _storage = StoragePool(
  node: 'lab-node',
  id: 'sample-storage',
  type: 'dir',
  active: true,
  enabled: true,
);

Future<AppController> _controller(DateTime Function() now) async {
  SharedPreferences.setMockInitialValues({});
  final controller =
      AppController(
          repository: ProfileRepository(
            await SharedPreferences.getInstance(),
            _Vault(),
          ),
          inventoryClock: now,
        )
        ..active = const ConnectionProfile(
          id: 'lab',
          name: 'A long connection name',
          endpoint: 'https://lab.example',
          allowInvalidCertificates: true,
          lastServerVersion: '9.2.0',
        )
        ..inventory = Inventory(
          nodes: const [_node],
          guests: const [_guest],
          fetchedAt: now(),
        )
        ..storages = const [_storage];
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  testWidgets('manual-refresh shell relabels inventory when it expires', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var now = DateTime.now();
    final controller = await _controller(() => now);
    const freshness = Key('shell-inventory-freshness');
    Text header() => tester.widget<Text>(find.byKey(freshness));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: AnimatedBuilder(
          animation: controller,
          builder: (_, _) => ShellPage(controller: controller),
        ),
      ),
    );
    controller.setForeground(false);
    controller.setForeground(true);
    await tester.pump();
    expect(header().data, 'Live snapshot');
    expect(find.textContaining('TLS UNVERIFIED'), findsWidgets);
    final homeScroll = find
        .descendant(
          of: find.byKey(const Key('home-overview-list')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Infrastructure'),
      300,
      scrollable: homeScroll,
    );
    expect(find.text('LIVE SNAPSHOT'), findsOneWidget);

    now = now.add(const Duration(minutes: 2));
    await tester.pump(const Duration(minutes: 2));
    expect(header().data, 'Last observed snapshot');
    expect(header().maxLines, isNull);
    expect(find.text('LIVE SNAPSHOT'), findsNothing);
    expect(find.text('LAST OBSERVED'), findsWidgets);
    expect(find.byKey(const Key('device-network-unavailable')), findsNothing);
    await tester.scrollUntilVisible(
      find.text('lab-node'),
      250,
      scrollable: homeScroll,
    );
    final semantics = tester.ensureSemantics();
    try {
      await tester.pump();
      expect(
        find.bySemanticsLabel('Last observed status: online'),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }

    controller.setDeviceNetworkState(DeviceNetworkState.unavailable);
    await tester.pump();
    expect(header().data, 'No default network');
    expect(find.byKey(const Key('device-network-unavailable')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('guest and node metrics distinguish stale data from no network', (
    tester,
  ) async {
    var now = DateTime.now();
    final controller = await _controller(() => now);
    const primary = Key('guest-primary-action');

    await tester.pumpWidget(
      MaterialApp(
        home: GuestPage(
          controller: controller,
          guest: _guest,
          profileId: 'lab',
          generation: controller.connectionGeneration,
        ),
      ),
    );
    final chip = find.byType(StatusChip);
    expect(tester.widget<StatusChip>(chip).lastObserved, isFalse);
    expect(
      tester.widget<FilledButton>(find.byKey(primary)).onPressed,
      isNotNull,
    );
    now = now.add(const Duration(minutes: 3));
    controller.notifyListeners();
    await tester.pump();
    expect(find.text('Last observed utilization'), findsOneWidget);
    expect(find.text('Live utilization'), findsNothing);
    expect(tester.widget<StatusChip>(chip).lastObserved, isTrue);
    expect(tester.widget<FilledButton>(find.byKey(primary)).onPressed, isNull);
    expect(
      find.text('A fresh inventory is required — actions are disabled.'),
      findsOneWidget,
    );
    expect(find.textContaining('No default network'), findsNothing);
    controller.setDeviceNetworkState(DeviceNetworkState.unavailable);
    await tester.pump();
    expect(
      find.text('No default network — actions are disabled.'),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(find.byKey(primary)).onPressed, isNull);

    await tester.pumpWidget(
      MaterialApp(
        home: NodePage(
          controller: controller,
          node: _node,
          profileId: 'lab',
          generation: controller.connectionGeneration,
        ),
      ),
    );
    expect(find.text('Last observed utilization'), findsOneWidget);
    expect(
      find.text('No default network. Check Wi-Fi or VPN.'),
      findsOneWidget,
    );
    expect(tester.widget<StatusChip>(chip).lastObserved, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'storage evidence stays last observed when storage refresh fails',
    (tester) async {
      final controller = await _controller(DateTime.now);
      await tester.pumpWidget(
        MaterialApp(
          home: StoragePage(
            controller: controller,
            storage: _storage,
            profileId: 'lab',
            generation: controller.connectionGeneration,
          ),
        ),
      );
      expect(
        tester.widget<StatusChip>(find.byType(StatusChip)).lastObserved,
        isFalse,
      );
      controller.storageMessage = 'Could not refresh storage.';
      controller.notifyListeners();
      await tester.pump();
      expect(find.text('Last observed capacity'), findsOneWidget);
      expect(find.text('Could not refresh storage.'), findsOneWidget);
      expect(
        tester.widget<StatusChip>(find.byType(StatusChip)).lastObserved,
        isTrue,
      );
    },
  );

  testWidgets('an open power confirmation cannot outlive fresh inventory', (
    tester,
  ) async {
    var now = DateTime.now();
    final controller = await _controller(() => now);
    controller.setForeground(false);
    controller.setForeground(true);
    await tester.pumpWidget(
      MaterialApp(
        home: GuestPage(
          controller: controller,
          guest: _guest,
          profileId: 'lab',
          generation: controller.connectionGeneration,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('guest-primary-action')));
    await tester.pumpAndSettle();
    final confirm = find.widgetWithText(FilledButton, 'Confirm');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);

    now = now.add(const Duration(minutes: 2));
    await tester.pump(const Duration(minutes: 2));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('A fresh inventory is required'),
      ),
      findsOneWidget,
    );

    controller.inventory = Inventory(
      nodes: const [_node],
      guests: const [_guest],
      fetchedAt: now,
    );
    controller.notifyListeners();
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
