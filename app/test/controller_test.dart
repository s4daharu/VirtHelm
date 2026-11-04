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

class _PausedStoreVault extends _Vault {
  final started = Completer<void>();
  final gate = Completer<void>();

  @override
  Future<void> store(String id, ApiCredentials credentials) async {
    if (!started.isCompleted) started.complete();
    await gate.future;
    await super.store(id, credentials);
  }
}

class _FailingStoreVault extends _Vault {
  @override
  Future<void> store(String id, ApiCredentials credentials) async {
    await super.store(id, credentials);
    throw StateError('Failed after write');
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
  Completer<ServerTaskStatus>? taskGate;
  Completer<void>? taskStarted;
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
    if (taskStarted?.isCompleted == false) taskStarted!.complete();
    if (taskGate != null) return taskGate!.future;
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

  test('overlapping profile saves cannot lose another profile', () async {
    final prefs = await SharedPreferences.getInstance();
    final vault = _PausedStoreVault();
    final repo = ProfileRepository(prefs, vault);
    final a = ConnectionProfile.create(name: 'A', address: 'https://a.example');
    final b = ConnectionProfile.create(name: 'B', address: 'https://b.example');
    const creds = ApiCredentials(tokenId: 'me@pve!test', secret: 'test');
    final first = repo.save(a, creds);
    final second = repo.save(b, creds);
    await vault.started.future;
    vault.gate.complete();
    await Future.wait([first, second]);
    expect(repo.readProfiles().map((profile) => profile.id), [a.id, b.id]);
    expect(vault.values.keys.toSet(), {a.id, b.id});
  });

  test(
    'a partial vault write is rolled back and a failed write does not poison the queue',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final vault = _FailingStoreVault();
      final repo = ProfileRepository(prefs, vault);
      final profile = ConnectionProfile.create(
        name: 'Lab',
        address: 'https://pve.local',
      );
      const creds = ApiCredentials(tokenId: 'me@pve!test', secret: 'test');
      await expectLater(repo.save(profile, creds), throwsStateError);
      expect(vault.values, isEmpty);
      expect(repo.readProfiles(), isEmpty);
      await repo.setActive(null);
      expect(repo.activeId, isNull);
    },
  );

  test(
    'deleted connections cannot be recreated by a late favorite update',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = ProfileRepository(prefs, _Vault());
      final profile = ConnectionProfile.create(
        name: 'Lab',
        address: 'https://pve.local',
      );
      await repo.save(
        profile,
        const ApiCredentials(tokenId: 'me@pve!test', secret: 'test'),
      );
      await repo.delete(profile.id);
      await expectLater(
        repo.setGuestFavorite(profile.id, 'qemu:pve1:101', true),
        throwsStateError,
      );
      expect(repo.readGuestFavorites(profile.id), isEmpty);
    },
  );

  test(
    'deletion cannot override a connection selected while vault I/O is pending',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final vault = _PausedVault();
      final repo = ProfileRepository(prefs, vault);
      final profiles = [
        for (final name in ['a', 'b', 'c'])
          ConnectionProfile.create(
            name: name,
            address: 'https://$name.example',
          ),
      ];
      for (final profile in profiles) {
        await repo.save(
          profile,
          const ApiCredentials(tokenId: 'me@pve!test', secret: 'test'),
        );
      }
      final ctl = AppController(
        repository: repo,
        gatewayFactory: (p, c) => _Gateway(),
      );
      addTearDown(ctl.dispose);
      await ctl.initialize();
      final deleting = ctl.deleteProfile(profiles.last.id);
      // Activation is intentionally started without waiting: repository writes
      // are serialized behind the pending deletion.
      final activating = ctl.activate(profiles[1]);
      vault.removeGate.complete();
      await Future.wait([deleting, activating]);
      expect(ctl.active!.id, profiles[1].id);
      expect(repo.activeId, profiles[1].id);
    },
  );

  test('a connection pending deletion cannot be reactivated', () async {
    final prefs = await SharedPreferences.getInstance();
    final vault = _PausedVault();
    final repo = ProfileRepository(prefs, vault);
    final a = ConnectionProfile.create(name: 'A', address: 'https://a.example');
    final b = ConnectionProfile.create(name: 'B', address: 'https://b.example');
    for (final profile in [a, b]) {
      await repo.save(
        profile,
        const ApiCredentials(tokenId: 'me@pve!test', secret: 'test'),
      );
    }
    final ctl = AppController(
      repository: repo,
      gatewayFactory: (p, c) => _Gateway(),
    );
    addTearDown(ctl.dispose);
    await ctl.initialize();
    final deleting = ctl.deleteProfile(a.id);
    await ctl.activate(a);
    expect(ctl.active!.id, b.id);
    vault.removeGate.complete();
    await deleting;
    expect(ctl.active!.id, b.id);
  });

  test(
    'a hung old-session poll never blocks or changes new-session tasks',
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
        name: 'A',
        address: 'https://a.example',
        tokenId: 'me@pve!test',
        secret: 'test',
      );
      final old = gateway;
      old.taskGate = Completer<ServerTaskStatus>();
      old.taskStarted = Completer<void>();
      await ctl.runAction(
        ctl.inventory!.guests.single,
        GuestAction.shutdown,
        profileId: ctl.active!.id,
      );
      await old.taskStarted!.future;
      await ctl.connect(
        name: 'B',
        address: 'https://b.example',
        tokenId: 'me@pve!test',
        secret: 'test',
      );
      gateway.taskResult = const ServerTaskStatus(
        status: 'stopped',
        exitStatus: 'OK',
      );
      final guest = ctl.inventory!.guests.single;
      final completed = Completer<void>();
      ctl.addListener(() {
        if (!completed.isCompleted &&
            ctl.tasks.isNotEmpty &&
            ctl.tasks.single.outcome == OperationOutcome.succeeded &&
            !ctl.isGuestActionBlocked(guest)) {
          completed.complete();
        }
      });
      await ctl.runAction(
        guest,
        GuestAction.shutdown,
        profileId: ctl.active!.id,
      );
      await completed.future.timeout(const Duration(seconds: 2));
      old.taskGate!.completeError(StateError('Old connection closed'));
      await Future<void>.delayed(Duration.zero);
      expect(ctl.tasks.single.outcome, OperationOutcome.succeeded);
      expect(ctl.active!.name, 'B');
    },
  );

  test('backgrounding during preflight prevents a late POST', () async {
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
      tokenId: 'me@pve!test',
      secret: 'test',
    );
    gateway.preflight = Completer<String>();
    final action = ctl.runAction(
      ctl.inventory!.guests.single,
      GuestAction.shutdown,
      profileId: ctl.active!.id,
    );
    ctl.setForeground(false);
    gateway.preflight!.complete('running');
    await expectLater(action, throwsA(isA<PveFailure>()));
    expect(gateway.submissions, 0);
    final before = gateway.inventoryCalls;
    ctl.setForeground(true);
    await ctl.refresh();
    expect(gateway.inventoryCalls, before + 1);
  });

  test(
    'disposal during onboarding does not persist a late connection',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final gateway = _Gateway()..inventoryGate = Completer<Inventory>();
      final repo = ProfileRepository(prefs, _Vault());
      final ctl = AppController(
        repository: repo,
        gatewayFactory: (p, c) => gateway,
      );
      final connecting = ctl.connect(
        name: 'Lab',
        address: 'https://pve.local',
        tokenId: 'me@pve!test',
        secret: 'test',
      );
      await Future<void>.delayed(Duration.zero);
      ctl.dispose();
      gateway.inventoryGate!.complete(Inventory.fromResources([]));
      await expectLater(connecting, throwsA(isA<PveFailure>()));
      expect(repo.readProfiles(), isEmpty);
    },
  );

  test('future-dated inventory cannot authorize writes', () async {
    final prefs = await SharedPreferences.getInstance();
    final ctl = AppController(repository: ProfileRepository(prefs, _Vault()));
    addTearDown(ctl.dispose);
    ctl.inventory = Inventory.fromResources(
      [],
      fetchedAt: DateTime.now().add(const Duration(hours: 1)),
    );
    expect(ctl.isInventoryFresh, isFalse);
  });

  test(
    'TLS opt-in persists across restart without affecting other profiles',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = ProfileRepository(prefs, _Vault());
      final seen = <ConnectionProfile>[];
      PveGateway factory(
        ConnectionProfile profile,
        ApiCredentials credentials,
      ) {
        seen.add(profile);
        return _Gateway();
      }

      final ctl = AppController(repository: repo, gatewayFactory: factory);
      addTearDown(ctl.dispose);
      await ctl.initialize();
      await ctl.connect(
        name: 'Lab',
        address: 'https://lab.example',
        tokenId: 'me@pve!app',
        secret: 'test-secret',
        allowInvalidCertificates: true,
      );
      expect(seen.every((profile) => profile.allowInvalidCertificates), isTrue);
      final lab = ctl.active!;
      await ctl.connect(
        name: 'Strict',
        address: 'https://strict.example',
        tokenId: 'me@pve!app',
        secret: 'test-secret',
      );
      expect(ctl.active!.allowInvalidCertificates, isFalse);
      expect(seen.last.allowInvalidCertificates, isFalse);
      await ctl.activate(lab);
      final restarted = AppController(
        repository: repo,
        gatewayFactory: factory,
      );
      addTearDown(restarted.dispose);
      await restarted.initialize();
      expect(restarted.active!.allowInvalidCertificates, isTrue);
      expect(seen.last.allowInvalidCertificates, isTrue);
      expect(repo.readProfiles().last.allowInvalidCertificates, isFalse);
    },
  );

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

  test(
    'terminal task reconciliation waits for a post-terminal inventory read',
    () async {
      final prefs = await SharedPreferences.getInstance();
      late _Gateway gateway;
      final ctl = AppController(
        repository: ProfileRepository(prefs, _Vault()),
        gatewayFactory: (profile, credentials) => gateway = _Gateway(),
      );
      addTearDown(ctl.dispose);
      await ctl.initialize();
      await ctl.connect(
        name: 'Lab',
        address: 'https://pve.local',
        tokenId: 'me@pve!test',
        secret: 'test',
      );
      final guest = ctl.inventory!.guests.single;
      gateway.taskGate = Completer<ServerTaskStatus>();
      gateway.taskStarted = Completer<void>();
      await ctl.runAction(
        guest,
        GuestAction.shutdown,
        profileId: ctl.active!.id,
      );
      await gateway.taskStarted!.future;
      final before = gateway.inventoryCalls;
      gateway.inventoryGate = Completer<Inventory>();
      final earlierRefresh = ctl.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(gateway.inventoryCalls, before + 1);

      gateway.taskGate!.complete(
        const ServerTaskStatus(status: 'stopped', exitStatus: 'OK'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(ctl.isGuestActionBlocked(guest), isTrue);

      final reconciled = Completer<void>();
      ctl.addListener(() {
        if (!reconciled.isCompleted && !ctl.isGuestActionBlocked(guest)) {
          reconciled.complete();
        }
      });
      gateway.inventoryGate!.complete(
        Inventory.fromResources([
          {'type': 'node', 'node': 'pve1', 'status': 'online'},
          {
            'type': 'qemu',
            'vmid': 101,
            'node': 'pve1',
            'name': 'Web',
            'status': 'stopped',
          },
        ]),
      );
      await earlierRefresh;
      await reconciled.future.timeout(const Duration(seconds: 3));
      expect(gateway.inventoryCalls, before + 2);
      expect(ctl.tasks.single.outcome, OperationOutcome.succeeded);
      expect(ctl.isGuestActionBlocked(guest), isFalse);
    },
  );
}
