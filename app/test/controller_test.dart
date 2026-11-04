import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:virthelm/core/app_controller.dart';
import 'package:virthelm/core/models.dart';
import 'package:virthelm/core/profile_repository.dart';
import 'package:virthelm/core/pve_api.dart';

class _Vault implements CredentialVault {
  final Map<String, ApiCredentials> values = {};
  @override
  Future<void> store(String id, ApiCredentials creds) async {
    values[id] = creds;
  }

  @override
  Future<ApiCredentials?> retrieve(String id) async => values[id];
  @override
  Future<void> remove(String id) async {
    values.remove(id);
  }
}

class _PausedVault extends _Vault {
  final removeGate = Completer<void>();

  @override
  Future<void> remove(String id) async {
    await removeGate.future;
    await super.remove(id);
  }
}

class _Gateway implements PveGateway {
  int submissions = 0;
  int inventoryCalls = 0;
  String status = 'running';
  Completer<Inventory>? inventoryGate;
  bool connected = true;
  Completer<String>? preflight;
  PveFailure? submissionError;
  ServerTaskStatus taskResult = const ServerTaskStatus(status: 'running');
  PveFailure? taskFailure;
  ReadCollection<StoragePool> storageResult = ReadCollection(
    values: const [
      StoragePool(
        node: 'pve1',
        id: 'local',
        type: 'dir',
        enabled: true,
        active: true,
        used: 512,
        total: 1024,
      ),
    ],
  );
  PveFailure? storageFailure;
  PveFailure? recentTaskFailure;
  ReadCollection<RecentServerTask> recentTaskResult = ReadCollection(
    values: const [
      RecentServerTask(
        upid: 'UPID:pve1:1:2:3:qmstart:101:user@pve:',
        node: 'pve1',
        operation: 'qmstart',
        resourceId: '101',
        status: 'stopped',
        exitStatus: 'OK',
      ),
    ],
  );
  @override
  Future<String> version() async => '9.2';
  @override
  Future<Inventory> inventory() {
    inventoryCalls++;
    final value = Inventory.fromResources([
      {'type': 'node', 'node': 'pve1', 'status': 'online', 'uptime': 3600},
      {
        'type': 'qemu',
        'vmid': 101,
        'node': 'pve1',
        'name': 'Web',
        'status': status,
        'uptime': 1800,
      },
    ]);
    return inventoryGate?.future ?? Future.value(value);
  }

  @override
  Future<ReadCollection<StoragePool>> storageOverview(
    List<String> nodes,
  ) async {
    if (storageFailure != null) throw storageFailure!;
    return storageResult;
  }

  @override
  Future<ReadCollection<RecentServerTask>> recentTasks(
    List<String> nodes,
  ) async {
    if (recentTaskFailure != null) throw recentTaskFailure!;
    return recentTaskResult;
  }

  @override
  Future<String> guestStatus(Guest guest) =>
      preflight?.future ?? Future.value(status);
  @override
  Future<String> submit(Guest guest, GuestAction action) async {
    submissions++;
    if (submissionError != null) throw submissionError!;
    return 'UPID:pve1:1234:123:abc:qmshutdown:101:operator@pve:';
  }

  @override
  Future<ServerTaskStatus> taskStatus(TrackedTask task) async {
    if (taskFailure != null) throw taskFailure!;
    return taskResult;
  }

  @override
  void close() {
    connected = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('profile secrets are outside unencrypted preference records', () async {
    final prefs = await SharedPreferences.getInstance();
    final vault = _Vault();
    final repo = ProfileRepository(prefs, vault);
    final profile = ConnectionProfile.create(
      name: 'Lab',
      address: 'https://pve.local',
    );
    const creds = ApiCredentials(tokenId: 'me@pve!app', secret: 's3cr3t');
    await repo.save(profile, creds);
    expect(prefs.getString('profile_metadata_v1'), isNot(contains('s3cr3t')));
    expect(
      prefs.getString('profile_metadata_v1'),
      isNot(contains('me@pve!app')),
    );
    expect((await vault.retrieve(profile.id))?.secret, 's3cr3t');
    await repo.delete(profile.id);
    expect(await vault.retrieve(profile.id), isNull);
  });

  test('submits a guarded write only once and tracks a UPID', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = ProfileRepository(prefs, _Vault());
    final gateways = <_Gateway>[];
    final ctl = AppController(
      repository: repo,
      gatewayFactory: (p, c) {
        final gateway = _Gateway();
        gateways.add(gateway);
        return gateway;
      },
    );
    addTearDown(ctl.dispose);
    await ctl.initialize();
    await ctl.connect(
      name: 'Lab',
      address: 'https://pve.local:8006',
      tokenId: 'me@pve!app',
      secret: 's3cr3t',
    );
    final guest = ctl.inventory!.guests.single;
    await ctl.runAction(guest, GuestAction.shutdown, profileId: ctl.active!.id);
    expect(gateways.last.submissions, 1);
    expect(ctl.tasks.length, 1);
    expect(ctl.tasks.single.outcome, OperationOutcome.running);
  });

  test('stale or changed guest state blocks dangerous mutation', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = ProfileRepository(prefs, _Vault());
    late _Gateway gateway;
    final ctl = AppController(
      repository: repo,
      gatewayFactory: (p, c) {
        gateway = _Gateway();
        return gateway;
      },
    );
    addTearDown(ctl.dispose);
    await ctl.initialize();
    await ctl.connect(
      name: 'Lab',
      address: 'https://pve.local',
      tokenId: 'me@pve!app',
      secret: 's3cr3t',
    );
    gateway.status = 'stopped';
    final guest = ctl.inventory!.guests.single;
    await expectLater(
      ctl.runAction(guest, GuestAction.shutdown, profileId: ctl.active!.id),
      throwsA(isA<PveFailure>()),
    );
    expect(gateway.submissions, 0);
  });

  test(
    'double submission is blocked during preflight and while task runs',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final gateways = <_Gateway>[];
      final ctl = AppController(
        repository: ProfileRepository(prefs, _Vault()),
        gatewayFactory: (p, c) {
          final gateway = _Gateway();
          gateways.add(gateway);
          return gateway;
        },
      );
      addTearDown(ctl.dispose);
      await ctl.initialize();
      await ctl.connect(
        name: 'Lab',
        address: 'https://pve.local',
        tokenId: 'me@pve!app',
        secret: 's3cr3t',
      );
      final gateway = gateways.last;
      final guest = ctl.inventory!.guests.single;
      final profileId = ctl.active!.id;
      gateway.preflight = Completer<String>();

      final first = ctl.runAction(
        guest,
        GuestAction.shutdown,
        profileId: profileId,
      );
      expect(ctl.isGuestActionBlocked(guest), isTrue);
      await expectLater(
        ctl.runAction(guest, GuestAction.shutdown, profileId: profileId),
        throwsA(isA<PveFailure>()),
      );
      expect(gateway.submissions, 0);
      gateway.preflight!.complete('running');
      await first;
      expect(gateway.submissions, 1);
      expect(ctl.isGuestActionBlocked(guest), isTrue);
      await expectLater(
        ctl.runAction(guest, GuestAction.reboot, profileId: profileId),
        throwsA(isA<PveFailure>()),
      );
      expect(gateway.submissions, 1);
    },
  );

  test('ambiguous POST failure blocks further writes to that guest', () async {
    final prefs = await SharedPreferences.getInstance();
    late _Gateway gateway;
    final ctl = AppController(
      repository: ProfileRepository(prefs, _Vault()),
      gatewayFactory: (p, c) => gateway = _Gateway(),
    );
    addTearDown(ctl.dispose);
    await ctl.initialize();
    await ctl.connect(
      name: 'Lab',
      address: 'https://pve.local',
      tokenId: 'me@pve!app',
      secret: 's3cr3t',
    );
    final guest = ctl.inventory!.guests.single;
    final profileId = ctl.active!.id;
    gateway.submissionError = const PveFailure(
      'Timed out after submit; check task history.',
      mayHaveExecuted: true,
    );
    await expectLater(
      ctl.runAction(guest, GuestAction.shutdown, profileId: profileId),
      throwsA(isA<PveFailure>()),
    );
    expect(ctl.isGuestActionBlocked(guest), isTrue);
    gateway.submissionError = null;
    await expectLater(
      ctl.runAction(guest, GuestAction.stop, profileId: profileId),
      throwsA(isA<PveFailure>()),
    );
    expect(gateway.submissions, 1);
  });

  test('replaced inventory snapshot cannot authorize a stale guest', () async {
    final prefs = await SharedPreferences.getInstance();
    late _Gateway gateway;
    final ctl = AppController(
      repository: ProfileRepository(prefs, _Vault()),
      gatewayFactory: (p, c) => gateway = _Gateway(),
    );
    addTearDown(ctl.dispose);
    await ctl.initialize();
    await ctl.connect(
      name: 'Lab',
      address: 'https://pve.local',
      tokenId: 'me@pve!app',
      secret: 's3cr3t',
    );
    final oldGuest = ctl.inventory!.guests.single;
    await ctl.refresh();
    await expectLater(
      ctl.runAction(oldGuest, GuestAction.shutdown, profileId: ctl.active!.id),
      throwsA(isA<PveFailure>()),
    );
    expect(gateway.submissions, 0);
  });

  test('profile activation during preflight cancels the old action', () async {
    final prefs = await SharedPreferences.getInstance();
    final gateways = <_Gateway>[];
    final ctl = AppController(
      repository: ProfileRepository(prefs, _Vault()),
      gatewayFactory: (p, c) {
        final gateway = _Gateway();
        gateways.add(gateway);
        return gateway;
      },
    );
    addTearDown(ctl.dispose);
    await ctl.initialize();
    await ctl.connect(
      name: 'Lab',
      address: 'https://pve.local',
      tokenId: 'me@pve!app',
      secret: 's3cr3t',
    );
    final previous = gateways.last;
    final guest = ctl.inventory!.guests.single;
    previous.preflight = Completer<String>();
    final action = ctl.runAction(
      guest,
      GuestAction.shutdown,
      profileId: ctl.active!.id,
    );
    await ctl.activate(ctl.active!);
    previous.preflight!.complete('running');
    await expectLater(action, throwsA(isA<PveFailure>()));
    expect(previous.submissions, 0);
    expect(gateways.last.submissions, 0);
    expect(ctl.tasks, isEmpty);
  });

  test(
    'terminal UPID result releases a guest for a new verified action',
    () async {
      final prefs = await SharedPreferences.getInstance();
      late _Gateway gateway;
      final ctl = AppController(
        repository: ProfileRepository(prefs, _Vault()),
        gatewayFactory: (p, c) => gateway = _Gateway(),
      );
      addTearDown(ctl.dispose);
      await ctl.initialize();
      await ctl.connect(
        name: 'Lab',
        address: 'https://pve.local',
        tokenId: 'me@pve!app',
        secret: 's3cr3t',
      );
      gateway.taskResult = const ServerTaskStatus(
        status: 'stopped',
        exitStatus: 'OK',
      );
      final guest = ctl.inventory!.guests.single;
      await ctl.runAction(
        guest,
        GuestAction.shutdown,
        profileId: ctl.active!.id,
      );
      // Polling is asynchronous and reconciliation replaces the old snapshot.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(ctl.tasks.single.outcome, OperationOutcome.succeeded);
      expect(ctl.isGuestActionBlocked(guest), isFalse);
      expect(ctl.inventory!.guests.single, isNot(same(guest)));
    },
  );

  test(
    'deleting an active profile invalidates preflight before vault I/O completes',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final vault = _PausedVault();
      final gateways = <_Gateway>[];
      final ctl = AppController(
        repository: ProfileRepository(prefs, vault),
        gatewayFactory: (p, c) {
          final gateway = _Gateway();
          gateways.add(gateway);
          return gateway;
        },
      );
      addTearDown(ctl.dispose);
      await ctl.initialize();
      await ctl.connect(
        name: 'Lab',
        address: 'https://pve.local',
        tokenId: 'me@pve!app',
        secret: 's3cr3t',
      );
      final gateway = gateways.last;
      final guest = ctl.inventory!.guests.single;
      final profileId = ctl.active!.id;
      gateway.preflight = Completer<String>();
      final action = ctl.runAction(
        guest,
        GuestAction.shutdown,
        profileId: profileId,
      );

      final deleting = ctl.deleteProfile(profileId);
      expect(ctl.active, isNull);
      gateway.preflight!.complete('running');
      await expectLater(action, throwsA(isA<PveFailure>()));
      expect(gateway.submissions, 0);

      vault.removeGate.complete();
      await deleting;
      expect(ctl.profiles, isEmpty);
    },
  );

  test('refresh loads storage and recent server task history', () async {
    final prefs = await SharedPreferences.getInstance();
    late _Gateway gateway;
    final ctl = AppController(
      repository: ProfileRepository(prefs, _Vault()),
      gatewayFactory: (p, c) => gateway = _Gateway(),
    );
    addTearDown(ctl.dispose);
    await ctl.initialize();
    await ctl.connect(
      name: 'Lab',
      address: 'https://pve.local',
      tokenId: 'me@pve!app',
      secret: 's3cr3t',
    );
    expect(ctl.storages.single.id, 'local');
    expect(ctl.serverTasks.single.operationLabel, 'Start VM');
    expect(ctl.storageMessage, isNull);
    expect(ctl.serverTaskMessage, isNull);

    gateway.storageResult = ReadCollection(
      values: const <StoragePool>[],
      permissionDeniedNodes: 1,
    );
    gateway.recentTaskResult = ReadCollection(
      values: const <RecentServerTask>[],
      failedNodes: 1,
    );
    await ctl.refresh();
    expect(ctl.storageMessage, contains('denied access'));
    expect(ctl.serverTaskMessage, contains('unavailable'));
  });

  test('supplemental 401 marks live inventory unsafe for mutations', () async {
    final prefs = await SharedPreferences.getInstance();
    late _Gateway gateway;
    final ctl = AppController(
      repository: ProfileRepository(prefs, _Vault()),
      gatewayFactory: (p, c) => gateway = _Gateway(),
    );
    addTearDown(ctl.dispose);
    await ctl.initialize();
    await ctl.connect(
      name: 'Lab',
      address: 'https://pve.local',
      tokenId: 'me@pve!app',
      secret: 's3cr3t',
    );
    expect(ctl.isInventoryFresh, isTrue);
    gateway.storageFailure = const PveFailure(
      'Authentication failed. Check or rotate your API token.',
      status: 401,
    );
    await ctl.refresh();
    expect(ctl.message, contains('Authentication failed'));
    expect(ctl.isInventoryFresh, isFalse);
    final guest = ctl.inventory!.guests.single;
    await expectLater(
      ctl.runAction(guest, GuestAction.shutdown, profileId: ctl.active!.id),
      throwsA(isA<PveFailure>()),
    );
    expect(gateway.submissions, 0);
  });

  test(
    'refresh is single-flight and does not issue overlapping inventory reads',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final gateways = <_Gateway>[];
      final ctl = AppController(
        repository: ProfileRepository(prefs, _Vault()),
        gatewayFactory: (p, c) {
          final gateway = _Gateway();
          gateways.add(gateway);
          return gateway;
        },
      );
      addTearDown(ctl.dispose);
      await ctl.initialize();
      await ctl.connect(
        name: 'Lab',
        address: 'https://pve.local',
        tokenId: 'me@pve!app',
        secret: 's3cr3t',
      );
      final gateway = gateways.last;
      final baseline = gateway.inventoryCalls;
      gateway.inventoryGate = Completer<Inventory>();
      final first = ctl.refresh();
      final second = ctl.refresh();
      expect(gateway.inventoryCalls, baseline + 1);
      gateway.inventoryGate!.complete(
        Inventory.fromResources([
          {'type': 'node', 'node': 'pve1', 'status': 'online'},
          {'type': 'qemu', 'vmid': 101, 'node': 'pve1', 'status': 'running'},
        ]),
      );
      await Future.wait([first, second]);
      expect(gateway.inventoryCalls, baseline + 1);
    },
  );

  test(
    'task verification TTL becomes unknown and keeps the guest blocked',
    () async {
      final prefs = await SharedPreferences.getInstance();
      late _Gateway gateway;
      final ctl = AppController(
        repository: ProfileRepository(prefs, _Vault()),
        gatewayFactory: (p, c) => gateway = _Gateway(),
        taskVerificationTtl: Duration.zero,
      );
      addTearDown(ctl.dispose);
      await ctl.initialize();
      await ctl.connect(
        name: 'Lab',
        address: 'https://pve.local',
        tokenId: 'me@pve!app',
        secret: 's3cr3t',
      );
      final guest = ctl.inventory!.guests.single;
      await ctl.runAction(
        guest,
        GuestAction.shutdown,
        profileId: ctl.active!.id,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(ctl.tasks.single.outcome, OperationOutcome.unknown);
      expect(ctl.isGuestActionBlocked(guest), isTrue);
      expect(gateway.submissions, 1);
    },
  );

  test(
    'same VMID in another profile cannot authorize the old profile action',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final gateways = <_Gateway>[];
      final ctl = AppController(
        repository: ProfileRepository(prefs, _Vault()),
        gatewayFactory: (p, c) {
          final gateway = _Gateway();
          gateways.add(gateway);
          return gateway;
        },
      );
      addTearDown(ctl.dispose);
      await ctl.initialize();
      await ctl.connect(
        name: 'Cluster A',
        address: 'https://a.example',
        tokenId: 'me@pve!app',
        secret: 'a-secret',
      );
      final profileA = ctl.active!.id;
      final guestA = ctl.inventory!.guests.single;
      await ctl.connect(
        name: 'Cluster B',
        address: 'https://b.example',
        tokenId: 'me@pve!app',
        secret: 'b-secret',
      );
      final submissionsBefore = gateways.fold<int>(
        0,
        (total, gateway) => total + gateway.submissions,
      );
      await expectLater(
        ctl.runAction(guestA, GuestAction.shutdown, profileId: profileA),
        throwsA(isA<PveFailure>()),
      );
      expect(ctl.active!.id, isNot(profileA));
      expect(
        gateways.fold<int>(0, (total, gateway) => total + gateway.submissions),
        submissionsBefore,
      );
    },
  );

  test(
    'repository rejects duplicate profile metadata before overwriting its secret',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final vault = _Vault();
      final repo = ProfileRepository(prefs, vault);
      const profile = ConnectionProfile(
        id: 'fixed-id',
        name: 'Lab',
        endpoint: 'https://pve.local:8006',
      );
      const first = ApiCredentials(tokenId: 'me@pve!app', secret: 'first');
      const second = ApiCredentials(tokenId: 'me@pve!app', secret: 'second');
      await repo.save(profile, first);
      await expectLater(repo.save(profile, second), throwsA(isA<StateError>()));
      expect((await vault.retrieve(profile.id))?.secret, 'first');
    },
  );

  test(
    'malformed guest inventory remains readable but cannot authorize writes',
    () async {
      final prefs = await SharedPreferences.getInstance();
      late _Gateway gateway;
      final ctl = AppController(
        repository: ProfileRepository(prefs, _Vault()),
        gatewayFactory: (p, c) => gateway = _Gateway(),
      );
      addTearDown(ctl.dispose);
      await ctl.initialize();
      await ctl.connect(
        name: 'Lab',
        address: 'https://pve.local',
        tokenId: 'me@pve!app',
        secret: 's3cr3t',
      );
      gateway.inventoryGate = Completer<Inventory>();
      final refresh = ctl.refresh();
      gateway.inventoryGate!.complete(
        Inventory.fromResources([
          {'type': 'node', 'node': 'pve1', 'status': 'online'},
          {'type': 'qemu', 'vmid': 101, 'node': 'pve1', 'status': 'running'},
          {'type': 'qemu', 'vmid': 101, 'status': 'running'},
        ]),
      );
      await refresh;
      expect(ctl.isInventoryFresh, isTrue);
      expect(ctl.isInventoryWriteSafe, isFalse);
      expect(ctl.inventoryWarning, contains('malformed guest'));
      final guest = ctl.inventory!.guests.single;
      await expectLater(
        ctl.runAction(guest, GuestAction.shutdown, profileId: ctl.active!.id),
        throwsA(isA<PveFailure>()),
      );
      expect(gateway.submissions, 0);
    },
  );

  test(
    'preflight 401 invalidates cached authorization for all writes',
    () async {
      final prefs = await SharedPreferences.getInstance();
      late _Gateway gateway;
      final ctl = AppController(
        repository: ProfileRepository(prefs, _Vault()),
        gatewayFactory: (p, c) => gateway = _Gateway(),
      );
      addTearDown(ctl.dispose);
      await ctl.initialize();
      await ctl.connect(
        name: 'Lab',
        address: 'https://pve.local',
        tokenId: 'me@pve!app',
        secret: 's3cr3t',
      );
      final guest = ctl.inventory!.guests.single;
      gateway.preflight = Completer<String>();
      final action = ctl.runAction(
        guest,
        GuestAction.shutdown,
        profileId: ctl.active!.id,
      );
      gateway.preflight!.completeError(
        const PveFailure(
          'Authentication failed. Check or rotate your API token.',
          status: 401,
        ),
      );
      await expectLater(action, throwsA(isA<PveFailure>()));
      expect(ctl.message, contains('Authentication failed'));
      expect(ctl.isInventoryFresh, isFalse);
      expect(gateway.submissions, 0);
    },
  );

  test(
    'task polling 401 invalidates cached authorization without claiming outcome',
    () async {
      final prefs = await SharedPreferences.getInstance();
      late _Gateway gateway;
      final ctl = AppController(
        repository: ProfileRepository(prefs, _Vault()),
        gatewayFactory: (p, c) => gateway = _Gateway(),
      );
      addTearDown(ctl.dispose);
      await ctl.initialize();
      await ctl.connect(
        name: 'Lab',
        address: 'https://pve.local',
        tokenId: 'me@pve!app',
        secret: 's3cr3t',
      );
      gateway.taskFailure = const PveFailure(
        'Authentication failed. Check or rotate your API token.',
        status: 401,
      );
      final guest = ctl.inventory!.guests.single;
      await ctl.runAction(
        guest,
        GuestAction.shutdown,
        profileId: ctl.active!.id,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(ctl.message, contains('Authentication failed'));
      expect(ctl.tasks.single.outcome, OperationOutcome.running);
      expect(ctl.isInventoryFresh, isFalse);
    },
  );

  test(
    'guest favorites persist per profile and are removed with profile',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final vault = _Vault();
      final repo = ProfileRepository(prefs, vault);
      const creds = ApiCredentials(tokenId: 'me@pve!app', secret: 'secret');
      const first = ConnectionProfile(
        id: 'profile-a',
        name: 'Cluster A',
        endpoint: 'https://a.example',
      );
      const second = ConnectionProfile(
        id: 'profile-b',
        name: 'Cluster B',
        endpoint: 'https://b.example',
      );
      await repo.save(first, creds);
      await repo.save(second, creds);
      await repo.setGuestFavorite(first.id, 'qemu:pve1:101', true);
      await repo.setGuestFavorite(second.id, 'lxc:pve2:202', true);

      expect(repo.readGuestFavorites(first.id), {'qemu:pve1:101'});
      expect(repo.readGuestFavorites(second.id), {'lxc:pve2:202'});

      await repo.delete(first.id);
      expect(repo.readGuestFavorites(first.id), isEmpty);
      expect(repo.readGuestFavorites(second.id), {'lxc:pve2:202'});
    },
  );

  test('controller favorites do not leak across connection profiles', () async {
    final prefs = await SharedPreferences.getInstance();
    final ctl = AppController(
      repository: ProfileRepository(prefs, _Vault()),
      gatewayFactory: (p, c) => _Gateway(),
    );
    addTearDown(ctl.dispose);
    await ctl.initialize();
    await ctl.connect(
      name: 'Cluster A',
      address: 'https://a.example',
      tokenId: 'me@pve!app',
      secret: 'a-secret',
    );
    final profileA = ctl.active!;
    final guestA = ctl.inventory!.guests.single;
    await ctl.setGuestFavorite(guestA, true);
    expect(ctl.isGuestFavorite(guestA), isTrue);

    await ctl.connect(
      name: 'Cluster B',
      address: 'https://b.example',
      tokenId: 'me@pve!app',
      secret: 'b-secret',
    );
    final guestB = ctl.inventory!.guests.single;
    expect(ctl.isGuestFavorite(guestB), isFalse);

    await ctl.activate(profileA);
    expect(ctl.isGuestFavorite(ctl.inventory!.guests.single), isTrue);
  });
}
