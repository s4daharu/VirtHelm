import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:virthelm/core/app_controller.dart';
import 'package:virthelm/core/app_preferences.dart';
import 'package:virthelm/core/device_connectivity.dart';
import 'package:virthelm/core/guest_saved_view.dart';
import 'package:virthelm/core/models.dart';
import 'package:virthelm/core/profile_repository.dart';
import 'package:virthelm/core/pve_api.dart';

class _Vault implements CredentialVault {
  final Map<String, ApiCredentials> values = {};
  int storeCalls = 0;

  @override
  Future<void> store(String id, ApiCredentials creds) async {
    storeCalls++;
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

class _FailNextStoreVault extends _Vault {
  bool failNextStore = false;

  @override
  Future<void> store(String id, ApiCredentials credentials) async {
    await super.store(id, credentials);
    if (failNextStore) {
      failNextStore = false;
      throw StateError('Failed after replacement write');
    }
  }
}

class _Gateway implements PveGateway, GuestPermissionGateway, GuestCloneGateway {
  int submissions = 0;
  int inventoryCalls = 0;
  int taskStatusCalls = 0;
  int taskLogCalls = 0;
  final List<int> taskLogStarts = [];
  int guestSnapshotCalls = 0;
  Completer<GuestSnapshotInventory>? guestSnapshotGate;
  PveFailure? guestSnapshotFailure;
  GuestSnapshotInventory guestSnapshotResult = const GuestSnapshotInventory(
    snapshots: [
      GuestSnapshot(name: 'current'),
      GuestSnapshot(name: 'before-upgrade'),
    ],
  );
  int guestConfigurationCalls = 0;
  Completer<GuestConfiguration>? guestConfigurationGate;
  PveFailure? guestConfigurationFailure;
  GuestConfiguration guestConfigurationResult = GuestConfiguration.fromApi({
    'cores': 4,
    'memory': 4096,
    'scsi0': 'local-lvm:vm-101-disk-0,size=64G',
  }, kind: 'qemu');
  int guestPermissionCalls = 0;
  PveFailure? guestPermissionFailure;
  GuestPermissionSnapshot guestPermissionResult = const GuestPermissionSnapshot(
    privileges: {'VM.Audit', 'VM.PowerMgmt', 'VM.Snapshot'},
  );
  int nextCloneVmid = 901;
  final List<int> clonePermissionVmids = [];
  final List<int> assertedCloneVmids = [];
  final Map<int, GuestPermissionSnapshot> clonePermissionResults = {};
  int cloneSubmissions = 0;
  PveFailure? cloneAvailabilityFailure;
  PveFailure? cloneSubmissionFailure;
  int guestMetricCalls = 0;
  final List<GuestMetricTimeframe> guestMetricTimeframes = [];
  Completer<GuestMetricSeries>? guestMetricGate;
  PveFailure? guestMetricFailure;
  GuestMetricSeries guestMetricResult = GuestMetricSeries(
    points: [
      GuestMetricPoint(
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          1700000000000,
          isUtc: true,
        ),
        cpuFraction: 0.2,
        memoryFraction: 0.4,
      ),
    ],
  );
  int nodeMetricCalls = 0;
  final List<NodeMetricTimeframe> nodeMetricTimeframes = [];
  Completer<NodeMetricSeries>? nodeMetricGate;
  PveFailure? nodeMetricFailure;
  NodeMetricSeries nodeMetricResult = NodeMetricSeries(
    points: [
      NodeMetricPoint(
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          1700000000000,
          isUtc: true,
        ),
        cpuFraction: 0.25,
        memoryFraction: 0.5,
      ),
    ],
  );
  int storageMetricCalls = 0;
  final List<StorageMetricTimeframe> storageMetricTimeframes = [];
  Completer<StorageMetricSeries>? storageMetricGate;
  PveFailure? storageMetricFailure;
  StorageMetricSeries storageMetricResult = StorageMetricSeries(
    points: [
      StorageMetricPoint(
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          1700000000000,
          isUtc: true,
        ),
        usedBytes: 512,
        totalBytes: 1024,
      ),
    ],
  );
  String status = 'running';
  String serverVersion = '9.2';
  PveFailure? versionFailure;
  PveFailure? inventoryFailure;
  List<dynamic>? inventoryResources;
  Completer<Inventory>? inventoryGate;
  bool connected = true;
  Completer<String>? preflight;
  PveFailure? submissionError;
  ServerTaskStatus taskResult = const ServerTaskStatus(status: 'running');
  PveFailure? taskFailure;
  Completer<ServerTaskStatus>? taskGate;
  Completer<void>? taskStarted;
  Completer<TaskLogResult>? logGate;
  PveFailure? logFailure;
  TaskLogResult logResult = const TaskLogResult(
    entries: [TaskLogEntry(number: 1, text: 'Task started')],
    malformedRecords: 0,
  );
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
  Future<String> version() async {
    if (versionFailure != null) throw versionFailure!;
    return serverVersion;
  }

  @override
  Future<Inventory> inventory() {
    inventoryCalls++;
    if (inventoryFailure != null) return Future.error(inventoryFailure!);
    final value = Inventory.fromResources(
      inventoryResources ??
          [
            {
              'type': 'node',
              'node': 'pve1',
              'status': 'online',
              'uptime': 3600,
            },
            {
              'type': 'qemu',
              'vmid': 101,
              'node': 'pve1',
              'name': 'Web',
              'status': status,
              'uptime': 1800,
            },
          ],
    );
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
    taskStatusCalls++;
    if (taskStarted?.isCompleted == false) taskStarted!.complete();
    if (taskGate != null) return taskGate!.future;
    if (taskFailure != null) throw taskFailure!;
    return taskResult;
  }

  @override
  Future<TaskLogResult> taskLog(
    String node,
    String upid, {
    int start = 0,
  }) async {
    taskLogCalls++;
    taskLogStarts.add(start);
    if (logGate != null) return logGate!.future;
    if (logFailure != null) throw logFailure!;
    return logResult;
  }

  @override
  Future<GuestSnapshotInventory> guestSnapshots(Guest guest) async {
    guestSnapshotCalls++;
    if (guestSnapshotGate != null) return guestSnapshotGate!.future;
    if (guestSnapshotFailure != null) throw guestSnapshotFailure!;
    return guestSnapshotResult;
  }

  @override
  Future<GuestConfiguration> guestConfiguration(Guest guest) async {
    guestConfigurationCalls++;
    if (guestConfigurationGate != null) return guestConfigurationGate!.future;
    if (guestConfigurationFailure != null) throw guestConfigurationFailure!;
    return guestConfigurationResult;
  }

  @override
  Future<GuestPermissionSnapshot> guestPermissions(Guest guest) async {
    guestPermissionCalls++;
    if (guestPermissionFailure != null) throw guestPermissionFailure!;
    return guestPermissionResult;
  }

  @override
  Future<int> nextFreeVmid() async => nextCloneVmid;

  @override
  Future<void> assertVmidAvailable(int vmid) async {
    assertedCloneVmids.add(vmid);
    if (cloneAvailabilityFailure != null) throw cloneAvailabilityFailure!;
  }

  @override
  Future<GuestPermissionSnapshot> permissionsForVmid(int vmid) async {
    clonePermissionVmids.add(vmid);
    return clonePermissionResults[vmid] ??
        const GuestPermissionSnapshot(privileges: <String>{});
  }

  @override
  Future<String> cloneTemplate(
    Guest source,
    GuestCloneRequest request,
  ) async {
    cloneSubmissions++;
    if (cloneSubmissionFailure != null) throw cloneSubmissionFailure!;
    return 'UPID:pve1:1234:123:abc:qmclone:${source.vmid}:operator@pve:';
  }

  @override
  Future<GuestMetricSeries> guestMetrics(
    Guest guest,
    GuestMetricTimeframe timeframe,
  ) async {
    guestMetricCalls++;
    guestMetricTimeframes.add(timeframe);
    if (guestMetricGate != null) return guestMetricGate!.future;
    if (guestMetricFailure != null) throw guestMetricFailure!;
    return guestMetricResult;
  }

  @override
  Future<NodeMetricSeries> nodeMetrics(
    String node,
    NodeMetricTimeframe timeframe,
  ) async {
    nodeMetricCalls++;
    nodeMetricTimeframes.add(timeframe);
    if (nodeMetricGate != null) return nodeMetricGate!.future;
    if (nodeMetricFailure != null) throw nodeMetricFailure!;
    return nodeMetricResult;
  }

  @override
  Future<StorageMetricSeries> storageMetrics(
    StoragePool storage,
    StorageMetricTimeframe timeframe,
  ) async {
    storageMetricCalls++;
    storageMetricTimeframes.add(timeframe);
    if (storageMetricGate != null) return storageMetricGate!.future;
    if (storageMetricFailure != null) throw storageMetricFailure!;
    return storageMetricResult;
  }

  @override
  void close() {
    connected = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'candidate connection check reports limited inventory without persistence',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final vault = _Vault();
      final repo = ProfileRepository(prefs, vault);
      final gateway = _Gateway()
        ..serverVersion = '9.2.8'
        ..inventoryFailure = const PveFailure(
          'Permission denied for cluster inventory.',
          status: 403,
        );
      final ctl = AppController(
        repository: repo,
        gatewayFactory: (profile, credentials) => gateway,
      );
      addTearDown(ctl.dispose);

      final result = await ctl.verifyConnectionConfiguration(
        name: 'Lab',
        address: 'https://pve.local',
        tokenId: 'me@pve!test',
        secret: 'test-secret',
      );

      expect(result.serverVersion, '9.2.8');
      expect(result.inventoryAccessible, isFalse);
      expect(result.permissionLimited, isTrue);
      expect(result.inventoryStatus, 403);
      expect(repo.readProfiles(), isEmpty);
      expect(vault.values, isEmpty);
      expect(vault.storeCalls, 0);
      expect(ctl.active, isNull);
    },
  );

  test(
    'saved connection test refreshes version metadata without rewriting token',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final vault = _Vault();
      final repo = ProfileRepository(prefs, vault);
      final profile = ConnectionProfile.create(
        name: 'Lab',
        address: 'https://pve.local',
      ).withServerVersion('8.4.0');
      await repo.save(
        profile,
        const ApiCredentials(tokenId: 'me@pve!test', secret: 'test-secret'),
      );
      await repo.setActive(null);
      expect(vault.storeCalls, 1);

      final ctl = AppController(
        repository: repo,
        gatewayFactory: (candidate, credentials) =>
            _Gateway()..serverVersion = '9.2.8',
      );
      addTearDown(ctl.dispose);
      ctl.profiles = repo.readProfiles();

      final result = await ctl.testSavedConnection(profile.id);

      expect(result.inventoryAccessible, isTrue);
      expect(result.serverVersion, '9.2.8');
      expect(repo.readProfiles().single.lastServerVersion, '9.2.8');
      expect(vault.storeCalls, 1);
      expect(ctl.active, isNull);
    },
  );

  test(
    'initialize preserves explicit chooser state when no profile is selected',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = ProfileRepository(prefs, _Vault());
      final profiles = [
        ConnectionProfile.create(name: 'A', address: 'https://a.example'),
        ConnectionProfile.create(name: 'B', address: 'https://b.example'),
      ];
      for (final profile in profiles) {
        await repo.save(
          profile,
          const ApiCredentials(tokenId: 'me@pve!test', secret: 'test-secret'),
        );
      }
      await repo.setActive(null);
      var gatewayCreations = 0;
      final ctl = AppController(
        repository: repo,
        gatewayFactory: (profile, credentials) {
          gatewayCreations++;
          return _Gateway();
        },
      );
      addTearDown(ctl.dispose);

      await ctl.initialize();

      expect(ctl.initialized, isTrue);
      expect(ctl.profiles, hasLength(2));
      expect(ctl.active, isNull);
      expect(repo.activeId, isNull);
      expect(gatewayCreations, 0);
    },
  );

  test(
    'guest performance inspection is read-only and session isolated',
    () async {
      final prefs = await SharedPreferences.getInstance();
      late _Gateway gateway;
      final ctl = AppController(
        repository: ProfileRepository(prefs, _Vault()),
        gatewayFactory: (profile, credentials) => gateway = _Gateway(),
      );
      addTearDown(ctl.dispose);
      await ctl.connect(
        name: 'Lab',
        address: 'https://pve.local',
        tokenId: 'me@pve!test',
        secret: 'test',
      );

      final guest = ctl.inventory!.guests.single;
      final generation = ctl.connectionGeneration;
      final series = await ctl.inspectGuestMetrics(
        profileId: ctl.active!.id,
        generation: generation,
        guest: guest,
        timeframe: GuestMetricTimeframe.day,
      );
      expect(series?.points.single.cpuFraction, 0.2);
      expect(gateway.guestMetricCalls, 1);
      expect(gateway.guestMetricTimeframes, [GuestMetricTimeframe.day]);
      expect(gateway.submissions, 0);

      final stale = await ctl.inspectGuestMetrics(
        profileId: ctl.active!.id,
        generation: generation - 1,
        guest: guest,
        timeframe: GuestMetricTimeframe.hour,
      );
      expect(stale, isNull);
      expect(gateway.guestMetricCalls, 1);
    },
  );

  test('guest snapshot inspection is read-only and session isolated', () async {
    final prefs = await SharedPreferences.getInstance();
    late _Gateway gateway;
    final ctl = AppController(
      repository: ProfileRepository(prefs, _Vault()),
      gatewayFactory: (profile, credentials) => gateway = _Gateway(),
    );
    addTearDown(ctl.dispose);
    await ctl.connect(
      name: 'Lab',
      address: 'https://pve.local',
      tokenId: 'me@pve!test',
      secret: 'test',
    );

    final guest = ctl.inventory!.guests.single;
    final generation = ctl.connectionGeneration;
    final result = await ctl.inspectGuestSnapshots(
      profileId: ctl.active!.id,
      generation: generation,
      guest: guest,
    );
    expect(result?.snapshots.last.name, 'before-upgrade');
    expect(gateway.guestSnapshotCalls, 1);
    expect(gateway.submissions, 0);

    final stale = await ctl.inspectGuestSnapshots(
      profileId: ctl.active!.id,
      generation: generation - 1,
      guest: guest,
    );
    expect(stale, isNull);
    expect(gateway.guestSnapshotCalls, 1);
  });

  test(
    'guest configuration inspection is read-only and session isolated',
    () async {
      final prefs = await SharedPreferences.getInstance();
      late _Gateway gateway;
      final ctl = AppController(
        repository: ProfileRepository(prefs, _Vault()),
        gatewayFactory: (profile, credentials) => gateway = _Gateway(),
      );
      addTearDown(ctl.dispose);
      await ctl.connect(
        name: 'Lab',
        address: 'https://pve.local',
        tokenId: 'me@pve!test',
        secret: 'test',
      );

      final guest = ctl.inventory!.guests.single;
      final generation = ctl.connectionGeneration;
      final result = await ctl.inspectGuestConfiguration(
        profileId: ctl.active!.id,
        generation: generation,
        guest: guest,
      );
      expect(result?.visibleFieldCount, 3);
      expect(gateway.guestConfigurationCalls, 1);
      expect(gateway.submissions, 0);

      final stale = await ctl.inspectGuestConfiguration(
        profileId: ctl.active!.id,
        generation: generation - 1,
        guest: guest,
      );
      expect(stale, isNull);
      expect(gateway.guestConfigurationCalls, 1);
    },
  );

  test(
    'guest permission inspection is read-only and session isolated',
    () async {
      final prefs = await SharedPreferences.getInstance();
      late _Gateway gateway;
      final ctl = AppController(
        repository: ProfileRepository(prefs, _Vault()),
        gatewayFactory: (profile, credentials) => gateway = _Gateway(),
      );
      addTearDown(ctl.dispose);
      await ctl.connect(
        name: 'Lab',
        address: 'https://pve.local',
        tokenId: 'me@pve!test',
        secret: 'test',
      );

      final guest = ctl.inventory!.guests.single;
      final generation = ctl.connectionGeneration;
      final result = await ctl.inspectGuestPermissions(
        profileId: ctl.active!.id,
        generation: generation,
        guest: guest,
      );
      expect(result?.has('VM.PowerMgmt'), isTrue);
      expect(gateway.guestPermissionCalls, 1);
      expect(gateway.submissions, 0);

      final stale = await ctl.inspectGuestPermissions(
        profileId: ctl.active!.id,
        generation: generation - 1,
        guest: guest,
      );
      expect(stale, isNull);
      expect(gateway.guestPermissionCalls, 1);
    },
  );

  test(
    'node performance inspection is read-only and session isolated',
    () async {
      final prefs = await SharedPreferences.getInstance();
      late _Gateway gateway;
      final ctl = AppController(
        repository: ProfileRepository(prefs, _Vault()),
        gatewayFactory: (profile, credentials) => gateway = _Gateway(),
      );
      addTearDown(ctl.dispose);
      await ctl.connect(
        name: 'Lab',
        address: 'https://pve.local',
        tokenId: 'me@pve!test',
        secret: 'test',
      );

      final node = ctl.inventory!.nodes.single;
      final generation = ctl.connectionGeneration;
      final series = await ctl.inspectNodeMetrics(
        profileId: ctl.active!.id,
        generation: generation,
        node: node,
        timeframe: NodeMetricTimeframe.day,
      );
      expect(series?.points.single.cpuFraction, 0.25);
      expect(gateway.nodeMetricCalls, 1);
      expect(gateway.nodeMetricTimeframes, [NodeMetricTimeframe.day]);
      expect(gateway.submissions, 0);

      final stale = await ctl.inspectNodeMetrics(
        profileId: ctl.active!.id,
        generation: generation - 1,
        node: node,
        timeframe: NodeMetricTimeframe.hour,
      );
      expect(stale, isNull);
      expect(gateway.nodeMetricCalls, 1);
    },
  );

  test(
    'incident inbox retains failed tasks across incomplete reads and resolves on clean data',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final vault = _Vault();
      final repo = ProfileRepository(prefs, vault);
      final profile = ConnectionProfile.create(
        name: 'Lab',
        address: 'https://pve.local',
      );
      await repo.save(
        profile,
        const ApiCredentials(tokenId: 'me@pve!test', secret: 'test'),
      );
      final gateway = _Gateway()
        ..inventoryResources = [
          {'type': 'node', 'node': 'pve1', 'status': 'offline'},
        ]
        ..recentTaskResult = ReadCollection(
          values: const [
            RecentServerTask(
              upid: 'UPID:pve1:1:2:3:qmstart:101:user@pve:',
              node: 'pve1',
              operation: 'qmstart',
              resourceId: '101',
              status: 'stopped',
              exitStatus: 'ERROR',
            ),
          ],
        );
      final ctl = AppController(
        repository: repo,
        gatewayFactory: (profile, credentials) => gateway,
      );
      addTearDown(ctl.dispose);

      await ctl.activate(profile);
      expect(ctl.incidents, hasLength(2));
      expect(
        ctl.incidents.map((incident) => incident.title),
        containsAll(['Node pve1 is offline', 'Task failed: Start VM • 101']),
      );

      gateway.inventoryResources = [
        {'type': 'node', 'node': 'pve1', 'status': 'online'},
      ];
      gateway.recentTaskResult = ReadCollection(
        values: const <RecentServerTask>[],
        permissionDeniedNodes: 1,
      );
      await ctl.refresh();

      expect(
        ctl.incidents.map((incident) => incident.title),
        isNot(contains('Node pve1 is offline')),
      );
      expect(
        ctl.incidents.map((incident) => incident.title),
        contains('Task failed: Start VM • 101'),
      );
      expect(ctl.serverTaskMessage, contains('denied access'));

      gateway.recentTaskResult = ReadCollection(
        values: const <RecentServerTask>[],
      );
      await ctl.refresh();
      expect(ctl.incidents, isEmpty);
      expect(ctl.serverTaskMessage, isNull);
    },
  );

  test(
    'storage capacity inspection is read-only and session isolated',
    () async {
      final prefs = await SharedPreferences.getInstance();
      late _Gateway gateway;
      final ctl = AppController(
        repository: ProfileRepository(prefs, _Vault()),
        gatewayFactory: (profile, credentials) => gateway = _Gateway(),
      );
      addTearDown(ctl.dispose);
      await ctl.connect(
        name: 'Lab',
        address: 'https://pve.local',
        tokenId: 'me@pve!test',
        secret: 'test',
      );

      final storage = ctl.storages.single;
      final generation = ctl.connectionGeneration;
      final series = await ctl.inspectStorageMetrics(
        profileId: ctl.active!.id,
        generation: generation,
        storage: storage,
        timeframe: StorageMetricTimeframe.week,
      );
      expect(series?.points.single.usageFraction, 0.5);
      expect(gateway.storageMetricCalls, 1);
      expect(gateway.storageMetricTimeframes, [StorageMetricTimeframe.week]);
      expect(gateway.submissions, 0);

      final stale = await ctl.inspectStorageMetrics(
        profileId: ctl.active!.id,
        generation: generation - 1,
        storage: storage,
        timeframe: StorageMetricTimeframe.hour,
      );
      expect(stale, isNull);
      expect(gateway.storageMetricCalls, 1);
    },
  );

  test(
    'on-demand reads short-circuit while Android network is unavailable',
    () async {
      final prefs = await SharedPreferences.getInstance();
      late _Gateway gateway;
      final ctl = AppController(
        repository: ProfileRepository(prefs, _Vault()),
        gatewayFactory: (profile, credentials) => gateway = _Gateway(),
      );
      addTearDown(ctl.dispose);
      await ctl.connect(
        name: 'Lab',
        address: 'https://pve.local',
        tokenId: 'me@pve!test',
        secret: 'test',
      );

      final profileId = ctl.active!.id;
      final generation = ctl.connectionGeneration;
      final task = ctl.serverTasks.single;
      final guest = ctl.inventory!.guests.single;
      final node = ctl.inventory!.nodes.single;
      final storage = ctl.storages.single;
      final beforeTaskStatus = gateway.taskStatusCalls;
      final beforeTaskLog = gateway.taskLogCalls;
      final beforeGuestMetrics = gateway.guestMetricCalls;
      final beforeNodeMetrics = gateway.nodeMetricCalls;
      final beforeStorageMetrics = gateway.storageMetricCalls;

      ctl.setDeviceNetworkState(DeviceNetworkState.unavailable);

      expect(
        await ctl.inspectTask(
          profileId: profileId,
          generation: generation,
          node: task.node,
          upid: task.upid,
        ),
        isNull,
      );
      expect(
        await ctl.inspectGuestMetrics(
          profileId: profileId,
          generation: generation,
          guest: guest,
          timeframe: GuestMetricTimeframe.hour,
        ),
        isNull,
      );
      expect(
        await ctl.inspectNodeMetrics(
          profileId: profileId,
          generation: generation,
          node: node,
          timeframe: NodeMetricTimeframe.hour,
        ),
        isNull,
      );
      expect(gateway.taskStatusCalls, beforeTaskStatus);
      expect(gateway.taskLogCalls, beforeTaskLog);
      expect(gateway.guestMetricCalls, beforeGuestMetrics);
      expect(
        await ctl.inspectStorageMetrics(
          profileId: profileId,
          generation: generation,
          storage: storage,
          timeframe: StorageMetricTimeframe.hour,
        ),
        isNull,
      );
      expect(gateway.nodeMetricCalls, beforeNodeMetrics);
      expect(gateway.storageMetricCalls, beforeStorageMetrics);
      expect(gateway.submissions, 0);
    },
  );

  test(
    'on-demand metric authentication loss invalidates live write safety',
    () async {
      final prefs = await SharedPreferences.getInstance();
      late _Gateway gateway;
      final ctl = AppController(
        repository: ProfileRepository(prefs, _Vault()),
        gatewayFactory: (profile, credentials) => gateway = _Gateway(),
      );
      addTearDown(ctl.dispose);
      await ctl.connect(
        name: 'Lab',
        address: 'https://pve.local',
        tokenId: 'me@pve!test',
        secret: 'test',
      );

      final profileId = ctl.active!.id;
      var generation = ctl.connectionGeneration;
      final guest = ctl.inventory!.guests.single;
      gateway.guestMetricFailure = const PveFailure(
        'Authentication failed. Check or rotate your API token.',
        status: 401,
      );
      await expectLater(
        ctl.inspectGuestMetrics(
          profileId: profileId,
          generation: generation,
          guest: guest,
          timeframe: GuestMetricTimeframe.hour,
        ),
        throwsA(isA<PveFailure>()),
      );
      expect(ctl.message, contains('Authentication failed'));
      expect(ctl.isInventoryWriteSafe, isFalse);

      gateway.guestMetricFailure = null;
      await ctl.refresh();
      expect(ctl.message, isNull);
      expect(ctl.isInventoryWriteSafe, isTrue);

      generation = ctl.connectionGeneration;
      final node = ctl.inventory!.nodes.single;
      gateway.nodeMetricFailure = const PveFailure(
        'Authentication failed. Check or rotate your API token.',
        status: 401,
      );
      await expectLater(
        ctl.inspectNodeMetrics(
          profileId: profileId,
          generation: generation,
          node: node,
          timeframe: NodeMetricTimeframe.day,
        ),
        throwsA(isA<PveFailure>()),
      );
      expect(ctl.message, contains('Authentication failed'));
      expect(ctl.isInventoryWriteSafe, isFalse);

      gateway.nodeMetricFailure = null;
      await ctl.refresh();
      expect(ctl.message, isNull);
      expect(ctl.isInventoryWriteSafe, isTrue);

      generation = ctl.connectionGeneration;
      final storage = ctl.storages.single;
      gateway.storageMetricFailure = const PveFailure(
        'Authentication failed. Check or rotate your API token.',
        status: 401,
      );
      await expectLater(
        ctl.inspectStorageMetrics(
          profileId: profileId,
          generation: generation,
          storage: storage,
          timeframe: StorageMetricTimeframe.day,
        ),
        throwsA(isA<PveFailure>()),
      );
      expect(ctl.message, contains('Authentication failed'));
      expect(ctl.isInventoryWriteSafe, isFalse);
      expect(gateway.submissions, 0);
    },
  );

  test(
    'task inspection reads status and logs without posting, with partial 403',
    () async {
      final prefs = await SharedPreferences.getInstance();
      late _Gateway gateway;
      final ctl = AppController(
        repository: ProfileRepository(prefs, _Vault()),
        gatewayFactory: (profile, credentials) => gateway = _Gateway(),
      );
      addTearDown(ctl.dispose);
      await ctl.connect(
        name: 'Lab',
        address: 'https://pve.local',
        tokenId: 'me@pve!test',
        secret: 'test',
      );
      gateway.taskResult = const ServerTaskStatus(
        status: 'stopped',
        exitStatus: 'OK',
      );
      final task = ctl.serverTasks.single;
      final detail = await ctl.inspectTask(
        profileId: ctl.active!.id,
        generation: ctl.connectionGeneration,
        node: task.node,
        upid: task.upid,
      );
      expect(detail?.status?.succeeded, isTrue);
      expect(detail?.log?.entries.single.text, 'Task started');
      expect(gateway.taskLogCalls, 1);
      expect(gateway.taskLogStarts, [0]);
      expect(gateway.submissions, 0);

      final nextPage = await ctl.inspectTask(
        profileId: ctl.active!.id,
        generation: ctl.connectionGeneration,
        node: task.node,
        upid: task.upid,
        logStart: 100,
      );
      expect(nextPage?.status?.succeeded, isTrue);
      expect(gateway.taskLogStarts, [0, 100]);
      expect(gateway.submissions, 0);

      gateway.logFailure = const PveFailure('Permission denied.', status: 403);
      final partial = await ctl.inspectTask(
        profileId: ctl.active!.id,
        generation: ctl.connectionGeneration,
        node: task.node,
        upid: task.upid,
      );
      expect(partial?.status?.succeeded, isTrue);
      expect(partial?.log, isNull);
      expect(partial?.logError, contains('Permission denied'));
    },
  );

  test(
    'late task inspection cannot return logs from another session',
    () async {
      final prefs = await SharedPreferences.getInstance();
      late _Gateway gateway;
      final ctl = AppController(
        repository: ProfileRepository(prefs, _Vault()),
        gatewayFactory: (profile, credentials) => gateway = _Gateway(),
      );
      addTearDown(ctl.dispose);
      await ctl.connect(
        name: 'A',
        address: 'https://a.example',
        tokenId: 'me@pve!test',
        secret: 'test',
      );
      final old = gateway;
      old.logGate = Completer<TaskLogResult>();
      final task = ctl.serverTasks.single;
      final inspection = ctl.inspectTask(
        profileId: ctl.active!.id,
        generation: ctl.connectionGeneration,
        node: task.node,
        upid: task.upid,
      );
      await Future<void>.delayed(Duration.zero);
      expect(old.taskLogCalls, 1);
      await ctl.connect(
        name: 'B',
        address: 'https://b.example',
        tokenId: 'me@pve!test',
        secret: 'test',
      );
      old.logGate!.complete(old.logResult);
      expect(await inspection, isNull);
      expect(gateway.submissions, 0);
    },
  );

  test(
    'malformed profile metadata cannot brick valid profiles or new onboarding',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = ProfileRepository(prefs, _Vault());
      const valid = ConnectionProfile(
        id: 'valid-profile',
        name: 'Valid',
        endpoint: 'https://valid.example:8006',
      );
      await prefs.setString(
        'profile_metadata_v1',
        jsonEncode([
          {'id': 'bad-type', 'name': 7, 'endpoint': 'https://bad.example:8006'},
          valid.toJson(),
          {'id': 'unsafe', 'name': 'Unsafe', 'endpoint': 'http://bad.example'},
          valid.toJson(),
        ]),
      );

      final recovered = repo.readProfiles();
      expect(recovered, hasLength(2));
      expect(recovered.first.id, valid.id);
      expect(recovered.last.id, 'unsafe');
      // Unsafe stored origins remain removable metadata; DioPveGateway
      // independently refuses them before attaching credentials or sending I/O.
      expect(
        () => DioPveGateway(
          recovered.last,
          const ApiCredentials(tokenId: 'me@pve!test', secret: 'test'),
        ),
        throwsA(isA<FormatException>()),
      );

      await prefs.setString('profile_metadata_v1', '{malformed-json');
      expect(repo.readProfiles(), isEmpty);

      final replacement = ConnectionProfile.create(
        name: 'Replacement',
        address: 'https://replacement.example',
      );
      await repo.save(
        replacement,
        const ApiCredentials(tokenId: 'me@pve!test', secret: 'test'),
      );
      expect(repo.readProfiles().single.id, replacement.id);
    },
  );

  test('onboarding persists the observed server version', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = ProfileRepository(prefs, _Vault());
    final ctl = AppController(
      repository: repo,
      gatewayFactory: (profile, credentials) =>
          _Gateway()..serverVersion = '9.2.4',
    );
    addTearDown(ctl.dispose);

    await ctl.connect(
      name: 'Lab',
      address: 'https://pve.local',
      tokenId: 'me@pve!test',
      secret: 'secret',
    );

    expect(repo.readProfiles().single.lastServerVersion, '9.2.4');
    expect(ctl.active?.lastServerVersion, '9.2.4');
  });

  test('activation refreshes version without rewriting credentials', () async {
    final prefs = await SharedPreferences.getInstance();
    final vault = _Vault();
    final repo = ProfileRepository(prefs, vault);
    final profile = ConnectionProfile.create(
      name: 'Lab',
      address: 'https://pve.local',
    ).withServerVersion('8.4.0');
    await repo.save(
      profile,
      const ApiCredentials(tokenId: 'me@pve!test', secret: 'secret'),
    );
    expect(vault.storeCalls, 1);

    final ctl = AppController(
      repository: repo,
      gatewayFactory: (profile, credentials) =>
          _Gateway()..serverVersion = '9.2.7',
    );
    addTearDown(ctl.dispose);
    await ctl.initialize();

    expect(ctl.active?.lastServerVersion, '9.2.7');
    expect(repo.readProfiles().single.lastServerVersion, '9.2.7');
    expect(vault.storeCalls, 1);
  });

  test('profile update preserves identity and local guest metadata', () async {
    final prefs = await SharedPreferences.getInstance();
    final vault = _Vault();
    final repo = ProfileRepository(prefs, vault);
    final profile = ConnectionProfile.create(
      name: 'Lab',
      address: 'https://pve.local',
    );
    const originalCredentials = ApiCredentials(
      tokenId: 'me@pve!old',
      secret: 'old-secret',
    );
    await repo.save(profile, originalCredentials);
    await repo.setGuestFavorite(profile.id, 'qemu:pve1:101', true);
    await repo.saveGuestView(
      profile.id,
      SavedGuestView.create(name: 'Running', status: 'running'),
    );

    final updated = ConnectionProfile(
      id: profile.id,
      name: 'Primary Lab',
      endpoint: 'https://new.example:8006',
      allowInvalidCertificates: true,
    );
    const replacementCredentials = ApiCredentials(
      tokenId: 'me@pve!new',
      secret: 'new-secret',
    );
    await repo.update(updated, replacementCredentials);

    expect(repo.readProfiles(), hasLength(1));
    expect(repo.readProfiles().single.id, profile.id);
    expect(repo.readProfiles().single.name, 'Primary Lab');
    expect(repo.activeId, profile.id);
    expect(repo.readGuestFavorites(profile.id), contains('qemu:pve1:101'));
    expect(repo.readGuestViews(profile.id).single.name, 'Running');
    final stored = await vault.retrieve(profile.id);
    expect(stored?.tokenId, replacementCredentials.tokenId);
    expect(stored?.secret, replacementCredentials.secret);
  });

  test(
    'failed profile update restores metadata and encrypted credentials',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final vault = _FailNextStoreVault();
      final repo = ProfileRepository(prefs, vault);
      final profile = ConnectionProfile.create(
        name: 'Lab',
        address: 'https://pve.local',
      );
      const original = ApiCredentials(
        tokenId: 'me@pve!old',
        secret: 'old-secret',
      );
      await repo.save(profile, original);
      vault.failNextStore = true;

      await expectLater(
        repo.update(
          ConnectionProfile(
            id: profile.id,
            name: 'Changed',
            endpoint: 'https://changed.example:8006',
          ),
          const ApiCredentials(tokenId: 'me@pve!new', secret: 'new-secret'),
        ),
        throwsStateError,
      );

      final persisted = repo.readProfiles().single;
      expect(persisted.id, profile.id);
      expect(persisted.name, profile.name);
      expect(persisted.endpoint, profile.endpoint);
      final stored = await vault.retrieve(profile.id);
      expect(stored?.tokenId, original.tokenId);
      expect(stored?.secret, original.secret);
    },
  );

  test(
    'controller profile edit reuses saved token and revalidates before persistence',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final vault = _Vault();
      final repo = ProfileRepository(prefs, vault);
      final profile = ConnectionProfile.create(
        name: 'Lab',
        address: 'https://pve.local',
      );
      const credentials = ApiCredentials(
        tokenId: 'me@pve!test',
        secret: 'test-secret',
      );
      await repo.save(profile, credentials);
      final createdGateways = <ConnectionProfile>[];
      final ctl = AppController(
        repository: repo,
        gatewayFactory: (candidate, credential) {
          createdGateways.add(candidate);
          expect(credential.tokenId, credentials.tokenId);
          expect(credential.secret, credentials.secret);
          return _Gateway();
        },
      );
      addTearDown(ctl.dispose);
      await ctl.initialize();

      await ctl.updateConnection(
        profileId: profile.id,
        name: 'Edited Lab',
        address: 'https://edited.example',
      );

      expect(createdGateways, isNotEmpty);
      expect(createdGateways.last.id, profile.id);
      expect(createdGateways.last.endpoint, 'https://edited.example:8006');
      expect(repo.readProfiles().single.id, profile.id);
      expect(repo.readProfiles().single.name, 'Edited Lab');
      final stored = await vault.retrieve(profile.id);
      expect(stored?.tokenId, credentials.tokenId);
      expect(stored?.secret, credentials.secret);
    },
  );

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

  test(
    'disposal during secure persistence rolls back a late connection',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final vault = _PausedStoreVault();
      final repo = ProfileRepository(prefs, vault);
      final ctl = AppController(
        repository: repo,
        gatewayFactory: (profile, credentials) => _Gateway(),
      );
      final connecting = ctl.connect(
        name: 'Lab',
        address: 'https://pve.local',
        tokenId: 'me@pve!test',
        secret: 'test',
      );
      await vault.started.future;
      ctl.dispose();
      vault.gate.complete();

      await expectLater(connecting, throwsA(isA<PveFailure>()));
      expect(repo.readProfiles(), isEmpty);
      expect(repo.activeId, isNull);
      expect(vault.values, isEmpty);
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

  test('template inventory can never authorize a power mutation', () async {
    final prefs = await SharedPreferences.getInstance();
    late _Gateway gateway;
    final ctl = AppController(
      repository: ProfileRepository(prefs, _Vault()),
      gatewayFactory: (profile, credentials) =>
          gateway = _Gateway()
            ..inventoryResources = [
              {'type': 'node', 'node': 'pve1', 'status': 'online'},
              {
                'type': 'qemu',
                'vmid': 900,
                'node': 'pve1',
                'name': 'Ubuntu template',
                'status': 'stopped',
                'template': 1,
              },
            ],
    );
    addTearDown(ctl.dispose);
    await ctl.initialize();
    await ctl.connect(
      name: 'Lab',
      address: 'https://pve.local',
      tokenId: 'me@pve!app',
      secret: 's3cr3t',
    );

    final template = ctl.inventory!.guests.single;
    expect(template.isTemplate, isTrue);
    await expectLater(
      ctl.runAction(template, GuestAction.start, profileId: ctl.active!.id),
      throwsA(isA<PveFailure>()),
    );
    expect(gateway.submissions, 0);
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
      expect(ctl.tasks.single.outcome, OperationOutcome.unknown);
      expect(ctl.isGuestActionBlocked(guest), isTrue);
      expect(gateway.taskStatusCalls, 1);
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

  test(
    'a favorite tap from an old profile cannot change a new profile',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = ProfileRepository(prefs, _Vault());
      final ctl = AppController(
        repository: repo,
        gatewayFactory: (profile, credentials) => _Gateway(),
      );
      addTearDown(ctl.dispose);
      await ctl.initialize();
      await ctl.connect(
        name: 'A',
        address: 'https://a.example',
        tokenId: 'me@pve!test',
        secret: 'test',
      );
      final oldProfile = ctl.active!.id;
      final oldGuest = ctl.inventory!.guests.single;
      await ctl.connect(
        name: 'B',
        address: 'https://b.example',
        tokenId: 'me@pve!test',
        secret: 'test',
      );
      final newProfile = ctl.active!.id;
      await ctl.toggleGuestFavorite(oldGuest, expectedProfileId: oldProfile);
      expect(repo.readGuestFavorites(newProfile), isEmpty);
      expect(repo.readGuestFavorites(oldProfile), isEmpty);
      expect(ctl.favoriteGuests, isEmpty);
      await ctl.toggleGuestFavorite(
        ctl.inventory!.guests.single,
        expectedProfileId: newProfile,
      );
      expect(repo.readGuestFavorites(newProfile), isNotEmpty);
      expect(repo.readGuestFavorites(oldProfile), isEmpty);
    },
  );

  test('saved guest views reject stale profile writes', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = ProfileRepository(prefs, _Vault());
    final a = ConnectionProfile.create(name: 'A', address: 'https://a.example');
    final b = ConnectionProfile.create(name: 'B', address: 'https://b.example');
    const credentials = ApiCredentials(tokenId: 'me@pve!test', secret: 'test');
    await repo.save(a, credentials);
    await repo.save(b, credentials);
    final ctl = AppController(
      repository: repo,
      gatewayFactory: (profile, credentials) => _Gateway(),
    );
    addTearDown(ctl.dispose);
    await ctl.initialize();
    await ctl.activate(a);
    final view = SavedGuestView.create(name: 'Stopped', status: 'stopped');
    await ctl.activate(b);

    expect(await ctl.saveGuestView(view, expectedProfileId: a.id), isNull);
    expect(repo.readGuestViews(a.id), isEmpty);
    expect(repo.readGuestViews(b.id), isEmpty);

    final saved = await ctl.saveGuestView(view, expectedProfileId: b.id);
    expect(saved?.name, 'Stopped');
    expect(ctl.guestSavedViews.single.name, 'Stopped');
    expect(repo.readGuestViews(a.id), isEmpty);
  });

  testWidgets('auto refresh stops in background and resumes in foreground', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    late _Gateway gateway;
    final controller = AppController(
      repository: ProfileRepository(prefs, _Vault()),
      gatewayFactory: (profile, credentials) => gateway = _Gateway(),
    );
    addTearDown(controller.dispose);
    await controller.connect(
      name: 'Lab',
      address: 'https://pve.local',
      tokenId: 'me@pve!app',
      secret: 'secret',
    );
    await controller.setAutoRefreshPreference(
      AutoRefreshPreference.every30Seconds,
    );
    final before = gateway.inventoryCalls;
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(gateway.inventoryCalls, before + 1);

    controller.setForeground(false);
    await tester.pump(const Duration(minutes: 1));
    expect(gateway.inventoryCalls, before + 1);

    controller.setForeground(true);
    await tester.pump();
    final onResume = gateway.inventoryCalls;
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();
    expect(gateway.inventoryCalls, onResume + 1);
    expect(gateway.submissions, 0);
    // Cancel periodic timer before test teardown.
    controller.setForeground(false);
  });

  test(
    'opt-in live counts restore after cold transport failure only',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final vault = _Vault();
      final repo = ProfileRepository(prefs, vault);
      final first = AppController(
        repository: repo,
        gatewayFactory: (p, c) => _Gateway(),
      );
      await first.initialize();
      await first.connect(
        name: 'Lab',
        address: 'https://pve.local',
        tokenId: 'me@pve!app',
        secret: 's3cr3t',
      );
      final id = first.active!.id;
      await first.setOfflineOverviewEnabled(true);
      expect(repo.readOfflineOverview(id)?.totalGuests, 1);
      first.dispose();

      late _Gateway offline;
      final restored = AppController(
        repository: ProfileRepository(prefs, vault),
        gatewayFactory: (p, c) => offline = _Gateway()
          ..versionFailure = const PveFailure(
            'DNS lookup failed.',
            transportFailure: PveTransportFailure.dnsFailure,
          ),
      );
      addTearDown(restored.dispose);
      await restored.initialize();
      expect(restored.active?.id, id);
      expect(restored.inventory, isNull);
      expect(restored.cachedOverview?.totalGuests, 1);
      expect(restored.cachedOverview?.runningGuests, 1);
      expect(restored.message, contains('DNS lookup failed'));
      expect(restored.isInventoryFresh, isFalse);
      expect(restored.isInventoryWriteSafe, isFalse);
      await expectLater(
        restored.runAction(
          const Guest(
            node: 'pve1',
            vmid: 101,
            kind: 'qemu',
            name: 'Web',
            status: 'running',
          ),
          GuestAction.shutdown,
          profileId: id,
        ),
        throwsA(isA<PveFailure>()),
      );
      expect(offline.submissions, 0);
    },
  );

  test('cache never appears for TLS or authentication errors', () async {
    final prefs = await SharedPreferences.getInstance();
    final vault = _Vault();
    final repo = ProfileRepository(prefs, vault);
    final connected = AppController(
      repository: repo,
      gatewayFactory: (p, c) => _Gateway(),
    );
    await connected.initialize();
    await connected.connect(
      name: 'Lab',
      address: 'https://pve.local',
      tokenId: 'me@pve!app',
      secret: 's3cr3t',
    );
    final id = connected.active!.id;
    await connected.setOfflineOverviewEnabled(true);
    connected.dispose();

    final tls = AppController(
      repository: ProfileRepository(prefs, vault),
      gatewayFactory: (p, c) =>
          _Gateway()
            ..versionFailure = const PveFailure('TLS validation failed.'),
    );
    await tls.initialize();
    expect(tls.cachedOverview, isNull);
    expect(repo.readOfflineOverview(id), isNotNull);
    tls.dispose();

    final revoked = AppController(
      repository: ProfileRepository(prefs, vault),
      gatewayFactory: (p, c) => _Gateway()
        ..versionFailure = const PveFailure(
          'Authentication failed.',
          status: 401,
        ),
    );
    addTearDown(revoked.dispose);
    await revoked.initialize();
    expect(revoked.cachedOverview, isNull);
    expect(repo.readOfflineOverview(id), isNull);
  });

  test(
    'successful inventory with supplemental 401 erases stored counts',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = ProfileRepository(prefs, _Vault());
      late _Gateway gateway;
      final ctl = AppController(
        repository: repo,
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
      final id = ctl.active!.id;
      await ctl.setOfflineOverviewEnabled(true);
      expect(repo.readOfflineOverview(id), isNotNull);
      gateway.storageFailure = const PveFailure(
        'Authentication failed.',
        status: 401,
      );
      await ctl.refresh();
      expect(repo.readOfflineOverview(id), isNull);
      expect(ctl.isInventoryWriteSafe, isFalse);
      expect(ctl.message, contains('Authentication failed'));
    },
  );

  test(
    'refresh transport failure restores counts without a live inventory',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = ProfileRepository(prefs, _Vault());
      late _Gateway gateway;
      final ctl = AppController(
        repository: repo,
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
      final id = ctl.active!.id;
      await ctl.setOfflineOverviewEnabled(true);
      ctl.inventory = null;
      gateway.inventoryFailure = const PveFailure(
        'Connection timed out.',
        transportFailure: PveTransportFailure.connectTimeout,
      );
      await ctl.refresh();
      expect(ctl.cachedOverview?.totalNodes, 1);
      expect(ctl.inventory, isNull);
      expect(ctl.isInventoryWriteSafe, isFalse);

      await ctl.setOfflineOverviewEnabled(false);
      expect(repo.readOfflineOverview(id), isNull);
      expect(ctl.cachedOverview, isNull);
    },
  );

  test(
    'on-demand task authentication loss purges offline overview counts',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = ProfileRepository(prefs, _Vault());
      late _Gateway gateway;
      final ctl = AppController(
        repository: repo,
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
      final id = ctl.active!.id;
      await ctl.setOfflineOverviewEnabled(true);
      expect(repo.readOfflineOverview(id), isNotNull);
      gateway.taskFailure = const PveFailure(
        'Authentication failed.',
        status: 401,
      );
      final result = await ctl.inspectTask(
        profileId: id,
        generation: ctl.connectionGeneration,
        node: 'pve1',
        upid: gateway.recentTaskResult.values.single.upid,
      );
      expect(result?.statusError, contains('Authentication failed'));
      expect(gateway.taskLogCalls, 0);
      expect(repo.readOfflineOverview(id), isNull);
      expect(ctl.message, contains('Authentication failed'));
      expect(ctl.isInventoryWriteSafe, isFalse);
    },
  );

  test(
    'Android network loss blocks writes and restores only after fresh GET',
    () async {
      final prefs = await SharedPreferences.getInstance();
      late _Gateway gateway;
      final ctl = AppController(
        repository: ProfileRepository(prefs, _Vault()),
        gatewayFactory: (profile, credentials) => gateway = _Gateway(),
      );
      addTearDown(ctl.dispose);
      await ctl.connect(
        name: 'Lab',
        address: 'https://pve.local',
        tokenId: 'me@pve!app',
        secret: 'secret',
      );
      final guest = ctl.inventory!.guests.single;
      final profileId = ctl.active!.id;
      final before = gateway.inventoryCalls;
      expect(ctl.isInventoryWriteSafe, isTrue);

      ctl.setDeviceNetworkState(DeviceNetworkState.unavailable);
      expect(ctl.isInventoryWriteSafe, isFalse);
      await ctl.refresh();
      expect(gateway.inventoryCalls, before);
      await expectLater(
        ctl.runAction(guest, GuestAction.stop, profileId: profileId),
        throwsA(isA<PveFailure>()),
      );
      expect(gateway.submissions, 0);
      ctl.setDeviceNetworkState(DeviceNetworkState.unknown);
      expect(ctl.isInventoryWriteSafe, isFalse);

      ctl.setDeviceNetworkState(DeviceNetworkState.available);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(gateway.inventoryCalls, before + 1);
      expect(ctl.isInventoryWriteSafe, isTrue);
      expect(gateway.submissions, 0);
    },
  );

  test(
    'cold offline profile reopens only after default network returns',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final vault = _Vault();
      final repo = ProfileRepository(prefs, vault);
      final initial = AppController(
        repository: repo,
        gatewayFactory: (profile, credentials) => _Gateway(),
      );
      await initial.connect(
        name: 'Lab',
        address: 'https://pve.local',
        tokenId: 'me@pve!app',
        secret: 'secret',
      );
      final id = initial.active!.id;
      initial.dispose();

      var gatewaysCreated = 0;
      final restored = AppController(
        repository: repo,
        gatewayFactory: (profile, credentials) {
          gatewaysCreated++;
          return _Gateway();
        },
      );
      addTearDown(restored.dispose);
      restored.setDeviceNetworkState(DeviceNetworkState.unavailable);
      await restored.initialize();
      expect(restored.active?.id, id);
      expect(restored.inventory, isNull);
      expect(gatewaysCreated, 0);

      restored.setDeviceNetworkState(DeviceNetworkState.available);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(gatewaysCreated, 1);
      expect(restored.inventory, isNotNull);
      expect(restored.isInventoryWriteSafe, isTrue);
    },
  );

  test(
    'network loss invalidates an in-flight GET even if it resolves after recovery',
    () async {
      final prefs = await SharedPreferences.getInstance();
      late _Gateway gateway;
      final ctl = AppController(
        repository: ProfileRepository(prefs, _Vault()),
        gatewayFactory: (profile, credentials) => gateway = _Gateway(),
      );
      addTearDown(ctl.dispose);
      await ctl.connect(
        name: 'Lab',
        address: 'https://pve.local',
        tokenId: 'me@pve!app',
        secret: 'secret',
      );
      final before = gateway.inventoryCalls;
      final staleRead = Completer<Inventory>();
      final newRead = Completer<Inventory>();
      gateway.inventoryGate = staleRead;
      final oldRefresh = ctl.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(gateway.inventoryCalls, before + 1);

      ctl.setDeviceNetworkState(DeviceNetworkState.unavailable);
      ctl.setDeviceNetworkState(DeviceNetworkState.available);
      gateway.inventoryGate = newRead;
      staleRead.complete(ctl.inventory!);
      await oldRefresh;
      await Future<void>.delayed(Duration.zero);
      expect(gateway.inventoryCalls, before + 2);
      expect(ctl.isInventoryWriteSafe, isFalse);

      newRead.complete(
        Inventory.fromResources([
          {'type': 'node', 'node': 'pve1', 'status': 'online'},
          {
            'type': 'qemu',
            'vmid': 101,
            'node': 'pve1',
            'name': 'Web',
            'status': 'running',
          },
        ]),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(ctl.isInventoryWriteSafe, isTrue);
      expect(gateway.submissions, 0);
    },
  );

  test('template clone preflights capabilities and submits exactly once', () async {
    final prefs = await SharedPreferences.getInstance();
    late _Gateway gateway;
    final ctl = AppController(
      repository: ProfileRepository(prefs, _Vault()),
      gatewayFactory: (profile, credentials) => gateway = _Gateway()
        ..inventoryResources = [
          {'type': 'node', 'node': 'pve1', 'status': 'online'},
          {
            'type': 'qemu',
            'vmid': 900,
            'node': 'pve1',
            'name': 'ubuntu-template',
            'status': 'stopped',
            'template': 1,
          },
        ]
        ..clonePermissionResults[900] =
            const GuestPermissionSnapshot(privileges: {'VM.Clone'})
        ..clonePermissionResults[901] =
            const GuestPermissionSnapshot(privileges: {'VM.Allocate'}),
    );
    addTearDown(ctl.dispose);
    await ctl.initialize();
    await ctl.connect(
      name: 'Lab',
      address: 'https://pve.local',
      tokenId: 'me@pve!app',
      secret: 's3cr3t',
    );

    final source = ctl.inventory!.guests.single;
    expect(source.isTemplate, isTrue);
    expect(
      await ctl.suggestTemplateCloneVmid(
        profileId: ctl.active!.id,
        generation: ctl.connectionGeneration,
        source: source,
      ),
      901,
    );

    await ctl.runTemplateClone(
      source,
      const GuestCloneRequest(newVmid: 901, name: 'ubuntu-copy'),
      profileId: ctl.active!.id,
    );

    expect(gateway.clonePermissionVmids, [900, 901]);
    expect(gateway.assertedCloneVmids, [901]);
    expect(gateway.cloneSubmissions, 1);
    expect(ctl.tasks, hasLength(1));
    expect(ctl.tasks.single.title, contains('ubuntu-copy (901)'));
    expect(ctl.tasks.single.outcome, OperationOutcome.running);
    expect(ctl.isGuestActionBlocked(source), isTrue);
  });

  test('template clone stops before POST when destination allocation is absent', () async {
    final prefs = await SharedPreferences.getInstance();
    late _Gateway gateway;
    final ctl = AppController(
      repository: ProfileRepository(prefs, _Vault()),
      gatewayFactory: (profile, credentials) => gateway = _Gateway()
        ..inventoryResources = [
          {'type': 'node', 'node': 'pve1', 'status': 'online'},
          {
            'type': 'lxc',
            'vmid': 900,
            'node': 'pve1',
            'name': 'debian-template',
            'status': 'stopped',
            'template': 1,
          },
        ]
        ..clonePermissionResults[900] =
            const GuestPermissionSnapshot(privileges: {'VM.Clone'}),
    );
    addTearDown(ctl.dispose);
    await ctl.initialize();
    await ctl.connect(
      name: 'Lab',
      address: 'https://pve.local',
      tokenId: 'me@pve!app',
      secret: 's3cr3t',
    );

    final source = ctl.inventory!.guests.single;
    await expectLater(
      ctl.runTemplateClone(
        source,
        const GuestCloneRequest(newVmid: 901, name: 'debian-copy'),
        profileId: ctl.active!.id,
      ),
      throwsA(
        isA<PveFailure>().having(
          (failure) => failure.status,
          'status',
          403,
        ),
      ),
    );

    expect(gateway.clonePermissionVmids, [900, 901]);
    expect(gateway.assertedCloneVmids, isEmpty);
    expect(gateway.cloneSubmissions, 0);
    expect(ctl.isGuestActionBlocked(source), isFalse);
  });

}
