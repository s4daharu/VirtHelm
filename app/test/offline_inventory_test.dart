import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:virthelm/core/app_controller.dart';
import 'package:virthelm/core/device_connectivity.dart';
import 'package:virthelm/core/models.dart';
import 'package:virthelm/core/offline_inventory.dart';
import 'package:virthelm/core/profile_repository.dart';
import 'package:virthelm/ui/shell.dart';

class _Vault implements CredentialVault {
  final Map<String, ApiCredentials> values = {};

  @override
  Future<void> store(String id, ApiCredentials credentials) async {
    values[id] = credentials;
  }

  @override
  Future<ApiCredentials?> retrieve(String id) async => values[id];

  @override
  Future<void> remove(String id) async {
    values.remove(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const profile = ConnectionProfile(
    id: 'lab',
    name: 'Lab',
    endpoint: 'https://pve.local:8006',
  );
  const credentials = ApiCredentials(
    tokenId: 'operator@pve!mobile',
    secret: 'secret',
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Inventory liveInventory(DateTime fetchedAt) => Inventory.fromResources([
    {
      'type': 'node',
      'node': 'node-a',
      'status': 'online',
      'cpu': 0.75,
      'mem': 4096,
      'maxmem': 8192,
      'uptime': 900,
    },
    {
      'type': 'qemu',
      'node': 'node-a',
      'vmid': 101,
      'name': 'private-vm',
      'status': 'running',
      'cpu': 0.5,
      'mem': 2048,
      'maxmem': 4096,
      'disk': 100,
      'maxdisk': 200,
      'tags': 'production;secret-tag',
      'pool': 'private-pool',
      'netin': 12345,
      'netout': 67890,
    },
    {
      'type': 'lxc',
      'node': 'node-a',
      'vmid': 202,
      'name': 'private-ct',
      'status': 'stopped',
      'template': 0,
    },
  ], fetchedAt: fetchedAt);

  test('offline inventory stores only the allowlisted stale identity fields', () {
    final now = DateTime.utc(2026, 11, 12, 5);
    final snapshot = OfflineInventorySnapshot.fromInventory(
      liveInventory(now.subtract(const Duration(hours: 2))),
    );
    expect(snapshot, isNotNull);

    final encoded = jsonEncode(snapshot!.toJson());
    expect(encoded, contains('node-a'));
    expect(encoded, contains('private-vm'));
    expect(encoded, contains('101'));
    expect(encoded, isNot(contains('secret-tag')));
    expect(encoded, isNot(contains('private-pool')));
    expect(encoded, isNot(contains('12345')));
    expect(encoded, isNot(contains('"cpu"')));
    expect(encoded, isNot(contains('"mem"')));
    expect(encoded, isNot(contains('"disk"')));

    final decoded = OfflineInventorySnapshot.fromJson(
      jsonDecode(encoded),
      now: now,
    );
    expect(decoded?.nodes.single.name, 'node-a');
    expect(decoded?.guests.length, 2);
    expect(decoded?.guests.first.name, 'private-vm');
    expect(decoded?.runningGuests, 1);
    expect(decoded?.stoppedGuests, 1);
  });

  test('offline inventory rejects stale, future, extra and ambiguous records', () {
    final now = DateTime.utc(2026, 11, 12, 5);
    final snapshot = OfflineInventorySnapshot.fromInventory(liveInventory(now))!;
    final record = snapshot.toJson();

    expect(
      OfflineInventorySnapshot.fromJson({
        ...record,
        'timestampMs': now
            .subtract(const Duration(hours: 25))
            .millisecondsSinceEpoch,
      }, now: now),
      isNull,
    );
    expect(
      OfflineInventorySnapshot.fromJson({
        ...record,
        'timestampMs': now
            .add(const Duration(seconds: 1))
            .millisecondsSinceEpoch,
      }, now: now),
      isNull,
    );
    expect(
      OfflineInventorySnapshot.fromJson({...record, 'unexpected': true}, now: now),
      isNull,
    );
    expect(
      OfflineInventorySnapshot.fromJson({...record, 'v': 2}, now: now),
      isNull,
    );

    final guests = List<Map<String, Object>>.from(
      (record['guests'] as List).map(
        (item) => Map<String, Object>.from(item as Map),
      ),
    );
    guests.add({...guests.first, 'name': 'duplicate'});
    expect(
      OfflineInventorySnapshot.fromJson({...record, 'guests': guests}, now: now),
      isNull,
    );

    final badIdentity = List<Map<String, Object>>.from(
      (record['guests'] as List).map(
        (item) => Map<String, Object>.from(item as Map),
      ),
    );
    badIdentity[0] = {...badIdentity[0], 'name': 'bad\u0000name'};
    expect(
      OfflineInventorySnapshot.fromJson(
        {...record, 'guests': badIdentity},
        now: now,
      ),
      isNull,
    );
  });

  test('detailed offline inventory is separate opt-in and purges on edit', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = ProfileRepository(prefs, _Vault());
    await repo.save(profile, credentials);
    final snapshot = OfflineInventorySnapshot.fromInventory(
      liveInventory(DateTime.now().toUtc()),
    )!;

    await repo.saveOfflineInventory(profile.id, snapshot);
    expect(repo.offlineInventoryEnabled(profile.id), isFalse);
    expect(repo.readOfflineInventory(profile.id), isNull);

    await repo.setOfflineInventoryEnabled(profile.id, true);
    await repo.saveOfflineInventory(profile.id, snapshot);
    expect(repo.readOfflineInventory(profile.id)?.guests.length, 2);
    expect(repo.offlineOverviewEnabled(profile.id), isFalse);

    await repo.updateConfigurationMetadata(
      const ConnectionProfile(
        id: 'lab',
        name: 'Renamed',
        endpoint: 'https://pve.local:8006',
      ),
    );
    expect(repo.offlineInventoryEnabled(profile.id), isTrue);
    expect(repo.readOfflineInventory(profile.id), isNull);
  });

  test('opt-out and profile deletion erase detailed stale inventory', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = ProfileRepository(prefs, _Vault());
    await repo.save(profile, credentials);
    final snapshot = OfflineInventorySnapshot.fromInventory(
      liveInventory(DateTime.now().toUtc()),
    )!;

    await repo.setOfflineInventoryEnabled(profile.id, true);
    await repo.saveOfflineInventory(profile.id, snapshot);
    await repo.setOfflineInventoryEnabled(profile.id, false);
    expect(repo.offlineInventoryEnabled(profile.id), isFalse);
    expect(repo.readOfflineInventory(profile.id), isNull);
    expect(prefs.get('offline_inventory_v1:lab'), isNull);

    await repo.setOfflineInventoryEnabled(profile.id, true);
    await repo.saveOfflineInventory(profile.id, snapshot);
    await repo.delete(profile.id);
    expect(repo.offlineInventoryEnabled(profile.id), isFalse);
    expect(repo.readOfflineInventory(profile.id), isNull);
    expect(prefs.get('offline_inventory_v1:lab'), isNull);
  });

  test('controller opt-in saves and opt-out removes a clean live snapshot', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = ProfileRepository(prefs, _Vault());
    await repo.save(profile, credentials);
    final controller = AppController(repository: repo);
    addTearDown(controller.dispose);
    controller.active = profile;
    controller.deviceNetworkState = DeviceNetworkState.available;
    controller.inventory = liveInventory(DateTime.now().toUtc());

    await controller.setOfflineInventoryEnabled(true);

    expect(controller.offlineInventoryEnabled, isTrue);
    expect(repo.readOfflineInventory(profile.id)?.guests.length, 2);
    expect(controller.cachedInventory, isNull);
    expect(controller.isInventoryWriteSafe, isTrue);

    await controller.setOfflineInventoryEnabled(false);

    expect(controller.offlineInventoryEnabled, isFalse);
    expect(repo.readOfflineInventory(profile.id), isNull);
  });

  testWidgets('cached Home inventory is visibly stale and non-interactive', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final repo = ProfileRepository(prefs, _Vault());
    final controller = AppController(repository: repo);
    addTearDown(controller.dispose);
    controller.active = profile;
    controller.cachedInventory = OfflineInventorySnapshot.fromInventory(
      liveInventory(DateTime.now().toUtc().subtract(const Duration(hours: 1))),
    );
    controller.deviceNetworkState = DeviceNetworkState.unavailable;

    await tester.pumpWidget(
      MaterialApp(home: ShellPage(controller: controller)),
    );

    expect(find.textContaining('CACHED INVENTORY'), findsOneWidget);
    expect(find.byKey(const ValueKey('offline-node-node-a')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('offline-guest-qemu-101')),
      findsOneWidget,
    );
    final cachedNodeTile = tester.widget<ListTile>(
      find.descendant(
        of: find.byKey(const ValueKey('offline-node-node-a')),
        matching: find.byType(ListTile),
      ),
    );
    final cachedGuestTile = tester.widget<ListTile>(
      find.descendant(
        of: find.byKey(const ValueKey('offline-guest-qemu-101')),
        matching: find.byType(ListTile),
      ),
    );
    expect(cachedNodeTile.onTap, isNull);
    expect(cachedGuestTile.onTap, isNull);
  });

  testWidgets('Guests uses a dedicated cached browser with no live actions', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final repo = ProfileRepository(prefs, _Vault());
    final controller = AppController(repository: repo);
    addTearDown(controller.dispose);
    controller.active = profile;
    controller.cachedInventory = OfflineInventorySnapshot.fromInventory(
      liveInventory(DateTime.now().toUtc()),
    );
    controller.deviceNetworkState = DeviceNetworkState.unavailable;

    await tester.pumpWidget(
      MaterialApp(home: ShellPage(controller: controller)),
    );
    await tester.tap(find.text('Guests'));
    await tester.pump();

    expect(find.byKey(const Key('offline-inventory-banner')), findsOneWidget);
    expect(find.byKey(const Key('offline-inventory-search')), findsOneWidget);
    expect(find.byKey(const Key('guest-create-qemu')), findsNothing);
    expect(find.byKey(const Key('guest-create-lxc')), findsNothing);
    expect(
      find.byKey(const ValueKey('offline-guest-qemu-101')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('offline-inventory-search')),
      '202',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('offline-guest-qemu-101')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('offline-guest-lxc-202')),
      findsOneWidget,
    );
  });

  testWidgets('Settings exposes detailed stale cache as a separate opt-in', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final repo = ProfileRepository(prefs, _Vault());
    final controller = AppController(repository: repo);
    addTearDown(controller.dispose);
    controller.active = profile;

    await tester.pumpWidget(
      MaterialApp(home: ShellPage(controller: controller)),
    );
    await tester.tap(find.text('Settings'));
    await tester.pump();

    expect(find.byKey(const Key('offline-overview-preference')), findsOneWidget);
    expect(find.byKey(const Key('offline-inventory-preference')), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(
        find.byKey(const Key('offline-inventory-preference')),
      ).value,
      isFalse,
    );
  });
}
