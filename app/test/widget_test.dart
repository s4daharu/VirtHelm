import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:virthelm/core/app_controller.dart';
import 'package:virthelm/core/app_preferences.dart';
import 'package:virthelm/core/device_connectivity.dart';
import 'package:virthelm/main.dart';
import 'package:virthelm/core/models.dart';
import 'package:virthelm/core/offline_overview.dart';
import 'package:virthelm/core/profile_repository.dart';
import 'package:virthelm/ui/connect_page.dart';
import 'package:virthelm/ui/connections_page.dart';
import 'package:virthelm/ui/guest_page.dart';
import 'package:virthelm/ui/node_page.dart';
import 'package:virthelm/ui/shell.dart';
import 'package:virthelm/ui/storage_page.dart';
import 'package:virthelm/ui/task_details_page.dart';
import 'package:virthelm/ui/theme.dart';

class _EmptyVault implements CredentialVault {
  @override
  Future<void> store(String id, ApiCredentials credentials) async {}
  @override
  Future<ApiCredentials?> retrieve(String id) async => null;
  @override
  Future<void> remove(String id) async {}
}

class _TaskInspectionController extends AppController {
  _TaskInspectionController(ProfileRepository repository)
    : super(repository: repository);

  final List<int> requestedStarts = [];

  @override
  Future<TaskInspection?> inspectTask({
    required String profileId,
    required int generation,
    required String node,
    required String upid,
    int logStart = 0,
  }) async {
    requestedStarts.add(logStart);
    return TaskInspection(
      status: const ServerTaskStatus(status: 'stopped', exitStatus: 'OK'),
      log: TaskLogResult(
        entries: [
          TaskLogEntry(
            number: logStart + 1,
            text: 'Read-only log entry $logStart',
          ),
        ],
        malformedRecords: logStart == 0 ? 99 : 0,
      ),
    );
  }
}

class _GuestMetricController extends AppController {
  _GuestMetricController(ProfileRepository repository)
    : super(repository: repository);

  final List<GuestMetricTimeframe> requestedTimeframes = [];

  @override
  Future<GuestMetricSeries?> inspectGuestMetrics({
    required String profileId,
    required int generation,
    required Guest guest,
    required GuestMetricTimeframe timeframe,
  }) async {
    requestedTimeframes.add(timeframe);
    return GuestMetricSeries(
      points: [
        GuestMetricPoint(
          timestamp: DateTime.utc(2026, 11, 5, 12),
          cpuFraction: 0.1,
          memoryFraction: 0.4,
        ),
        GuestMetricPoint(
          timestamp: DateTime.utc(2026, 11, 5, 13),
          cpuFraction: 0.3,
          memoryFraction: 0.6,
        ),
      ],
      malformedRecords: 1,
    );
  }
}

class _GuestSnapshotController extends AppController {
  _GuestSnapshotController(ProfileRepository repository)
    : super(repository: repository);

  final List<int> requestedVmids = [];
  final List<String> requestedBackupStorages = [];

  @override
  Future<GuestBackupArchiveInventory?> inspectGuestBackupArchives({
    required String profileId,
    required int generation,
    required Guest guest,
    required String storage,
  }) async {
    requestedBackupStorages.add(storage);
    return GuestBackupArchiveInventory(
      storage: storage,
      archives: [
        GuestBackupArchive(
          node: guest.node,
          storage: storage,
          volid: '$storage:backup/vzdump-qemu-101-2026_11_11-10_00_00.vma.zst',
          kind: guest.kind,
          vmid: guest.vmid,
          sizeBytes: 1024,
          createdAt: DateTime.utc(2026, 11, 11, 10),
        ),
      ],
      ignoredRecords: 1,
    );
  }

  @override
  Future<GuestSnapshotInventory?> inspectGuestSnapshots({
    required String profileId,
    required int generation,
    required Guest guest,
  }) async {
    requestedVmids.add(guest.vmid);
    return GuestSnapshotInventory(
      snapshots: [
        const GuestSnapshot(name: 'current'),
        GuestSnapshot(
          name: 'before-upgrade',
          parent: 'baseline',
          description: 'Before package update',
          createdAt: DateTime.utc(2026, 11, 8, 10),
          includesMemory: true,
        ),
      ],
      malformedRecords: 1,
    );
  }
}

class _GuestConfigurationController extends AppController {
  _GuestConfigurationController(ProfileRepository repository)
    : super(repository: repository);

  final List<int> requestedVmids = [];

  @override
  Future<GuestConfiguration?> inspectGuestConfiguration({
    required String profileId,
    required int generation,
    required Guest guest,
  }) async {
    requestedVmids.add(guest.vmid);
    return GuestConfiguration.fromApi({
      'cores': 4,
      'memory': 4096,
      'cpu': 'x86-64-v2-AES',
      'scsi0': 'local-lvm:vm-101-disk-0,size=64G',
      'net0': 'virtio=AA:BB:CC:DD:EE:FF,bridge=vmbr0',
      'cipassword': 'must-not-render',
      'args': 'secret=must-not-render',
    }, kind: guest.kind);
  }
}

class _GuestPermissionController extends AppController {
  _GuestPermissionController(ProfileRepository repository)
    : super(repository: repository);

  final List<int> requestedVmids = [];

  @override
  Future<GuestPermissionSnapshot?> inspectGuestPermissions({
    required String profileId,
    required int generation,
    required Guest guest,
  }) async {
    requestedVmids.add(guest.vmid);
    return const GuestPermissionSnapshot(
      privileges: {
        'VM.Audit',
        'VM.PowerMgmt',
        'VM.Snapshot',
        'VM.Config.Disk',
        'VM.GuestAgent.Audit',
      },
      malformedPrivileges: 1,
    );
  }
}

class _NodeMetricController extends AppController {
  _NodeMetricController(ProfileRepository repository)
    : super(repository: repository);

  final List<NodeMetricTimeframe> requestedTimeframes = [];

  @override
  Future<NodeMetricSeries?> inspectNodeMetrics({
    required String profileId,
    required int generation,
    required Node node,
    required NodeMetricTimeframe timeframe,
  }) async {
    requestedTimeframes.add(timeframe);
    return NodeMetricSeries(
      points: [
        NodeMetricPoint(
          timestamp: DateTime.utc(2026, 11, 6, 12),
          cpuFraction: 0.2,
          memoryFraction: 0.5,
        ),
        NodeMetricPoint(
          timestamp: DateTime.utc(2026, 11, 6, 13),
          cpuFraction: 0.4,
          memoryFraction: 0.75,
        ),
      ],
      malformedRecords: 1,
    );
  }
}

class _StorageMetricController extends AppController {
  _StorageMetricController(ProfileRepository repository)
    : super(repository: repository);

  final List<StorageMetricTimeframe> requestedTimeframes = [];

  @override
  Future<StorageMetricSeries?> inspectStorageMetrics({
    required String profileId,
    required int generation,
    required StoragePool storage,
    required StorageMetricTimeframe timeframe,
  }) async {
    requestedTimeframes.add(timeframe);
    return StorageMetricSeries(
      points: [
        StorageMetricPoint(
          timestamp: DateTime.utc(2026, 11, 6, 12),
          usedBytes: 512,
          totalBytes: 1024,
        ),
        StorageMetricPoint(
          timestamp: DateTime.utc(2026, 11, 6, 13),
          usedBytes: 768,
          totalBytes: 1024,
        ),
      ],
      malformedRecords: 1,
    );
  }
}

class _BlockingController extends AppController {
  _BlockingController(ProfileRepository repository)
    : super(repository: repository);

  final started = Completer<void>();
  final gate = Completer<void>();

  @override
  Future<ConnectionCheckResult> verifyConnectionConfiguration({
    required String name,
    required String address,
    String tokenId = '',
    String secret = '',
    bool allowInvalidCertificates = false,
    String? existingProfileId,
  }) async => ConnectionCheckResult(
    serverVersion: '9.2-test',
    inventoryAccessible: true,
    certificateVerificationEnabled: !allowInvalidCertificates,
    nodeCount: 1,
    guestCount: 1,
  );

  @override
  Future<void> connect({
    required String name,
    required String address,
    required String tokenId,
    required String secret,
    bool allowInvalidCertificates = false,
  }) async {
    if (!started.isCompleted) started.complete();
    await gate.future;
  }
}

class _RecordingController extends AppController {
  _RecordingController(ProfileRepository repository)
    : super(repository: repository);

  final List<bool> connections = [];
  final List<Map<String, Object?>> updates = [];
  int checks = 0;
  Object? connectionError;
  ConnectionCheckResult checkResult = const ConnectionCheckResult(
    serverVersion: '9.2-test',
    inventoryAccessible: true,
    certificateVerificationEnabled: true,
    nodeCount: 1,
    guestCount: 1,
  );

  @override
  Future<ConnectionCheckResult> verifyConnectionConfiguration({
    required String name,
    required String address,
    String tokenId = '',
    String secret = '',
    bool allowInvalidCertificates = false,
    String? existingProfileId,
  }) async {
    checks++;
    if (connectionError != null) throw connectionError!;
    return ConnectionCheckResult(
      serverVersion: checkResult.serverVersion,
      inventoryAccessible: checkResult.inventoryAccessible,
      certificateVerificationEnabled: !allowInvalidCertificates,
      nodeCount: checkResult.nodeCount,
      guestCount: checkResult.guestCount,
      inventoryMessage: checkResult.inventoryMessage,
      inventoryStatus: checkResult.inventoryStatus,
    );
  }

  @override
  Future<ConnectionCheckResult> testSavedConnection(String profileId) async {
    checks++;
    if (connectionError != null) throw connectionError!;
    final matches = profiles.where((profile) => profile.id == profileId);
    final insecure =
        matches.isNotEmpty && matches.first.allowInvalidCertificates;
    return ConnectionCheckResult(
      serverVersion: checkResult.serverVersion,
      inventoryAccessible: checkResult.inventoryAccessible,
      certificateVerificationEnabled: !insecure,
      nodeCount: checkResult.nodeCount,
      guestCount: checkResult.guestCount,
      inventoryMessage: checkResult.inventoryMessage,
      inventoryStatus: checkResult.inventoryStatus,
    );
  }

  @override
  Future<void> updateConnection({
    required String profileId,
    required String name,
    required String address,
    String tokenId = '',
    String secret = '',
    bool allowInvalidCertificates = false,
  }) async {
    updates.add({
      'profileId': profileId,
      'name': name,
      'address': address,
      'tokenId': tokenId,
      'secret': secret,
      'allowInvalidCertificates': allowInvalidCertificates,
    });
    if (connectionError != null) throw connectionError!;
  }

  @override
  Future<void> connect({
    required String name,
    required String address,
    required String tokenId,
    required String secret,
    bool allowInvalidCertificates = false,
  }) async {
    connections.add(allowInvalidCertificates);
    if (connectionError != null) throw connectionError!;
  }
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

Future<void> _advanceConnectionWizard(
  WidgetTester tester, {
  String name = 'Lab',
  String address = 'https://pve.local',
  String? tokenId = 'me@pve!test',
  String? secret = 'test-secret',
  bool toggleInsecure = false,
}) async {
  await tester.enterText(find.byKey(const Key('connection-name')), name);
  await tester.enterText(find.byKey(const Key('connection-url')), address);
  if (toggleInsecure) {
    await _tapVisible(tester, find.byKey(const Key('connection-tls-toggle')));
    await tester.pumpAndSettle();
  }
  await _tapVisible(tester, find.byKey(const Key('connection-next')));
  await tester.pumpAndSettle();
  if (tokenId != null) {
    await tester.enterText(
      find.byKey(const Key('connection-token-id')),
      tokenId,
    );
  }
  if (secret != null) {
    await tester.enterText(
      find.byKey(const Key('connection-token-secret')),
      secret,
    );
  }
  await _tapVisible(tester, find.byKey(const Key('connection-next')));
  await tester.pumpAndSettle();
  expect(find.text('Verify connection'), findsOneWidget);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('node performance history is explicit and session redacted', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = _NodeMetricController(
      ProfileRepository(prefs, _EmptyVault()),
    );
    addTearDown(controller.dispose);
    controller.active = const ConnectionProfile(
      id: 'a',
      name: 'A',
      endpoint: 'https://a.example',
    );
    controller.inventory = Inventory.fromResources([
      {
        'type': 'node',
        'node': 'pve1',
        'status': 'online',
        'cpu': 0.1,
        'mem': 1024,
        'maxmem': 4096,
        'uptime': 3600,
      },
    ]);

    await tester.pumpWidget(
      MaterialApp(home: ShellPage(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(controller.requestedTimeframes, isEmpty);

    await tester.scrollUntilVisible(
      find.text('pve1'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('pve1'));
    await tester.pumpAndSettle();
    expect(find.byType(NodePage), findsOneWidget);
    await tester.tap(find.byKey(const Key('node-metrics-tab')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('node-metrics-list')), findsOneWidget);
    expect(find.text('Performance history'), findsOneWidget);
    expect(controller.requestedTimeframes, isEmpty);

    await tester.tap(find.text('Load history'));
    await tester.pumpAndSettle();
    expect(controller.requestedTimeframes, [NodeMetricTimeframe.hour]);
    await tester.ensureVisible(find.textContaining('1 malformed ignored'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 malformed ignored'), findsOneWidget);
    await tester.ensureVisible(find.textContaining('Latest 40.0%'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Latest 40.0%'), findsOneWidget);
    expect(find.textContaining('Range 20.0%–40.0%'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('24 hours'),
      -200,
      scrollable: find.descendant(
        of: find.byKey(const Key('node-metrics-list')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('24 hours'));
    await tester.pumpAndSettle();
    expect(controller.requestedTimeframes, [NodeMetricTimeframe.hour]);
    expect(find.textContaining('Latest 40.0%'), findsNothing);
    await tester.tap(find.text('Load history'));
    await tester.pumpAndSettle();
    expect(controller.requestedTimeframes, [
      NodeMetricTimeframe.hour,
      NodeMetricTimeframe.day,
    ]);

    controller.active = const ConnectionProfile(
      id: 'b',
      name: 'B',
      endpoint: 'https://b.example',
    );
    controller.notifyListeners();
    await tester.pump();
    expect(find.text('Node unavailable'), findsWidgets);
    expect(find.textContaining('Latest 40.0%'), findsNothing);
    expect(find.text('pve1'), findsNothing);
  });

  testWidgets('storage capacity history is explicit and session redacted', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = _StorageMetricController(
      ProfileRepository(prefs, _EmptyVault()),
    );
    addTearDown(controller.dispose);
    controller.active = const ConnectionProfile(
      id: 'a',
      name: 'A',
      endpoint: 'https://a.example',
    );
    controller.inventory = Inventory.fromResources([
      {'type': 'node', 'node': 'pve1', 'status': 'online'},
    ]);
    controller.storages = const [
      StoragePool(
        node: 'pve1',
        id: 'local',
        type: 'dir',
        active: true,
        contentTypes: ['iso', 'backup'],
        used: 512,
        total: 1024,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(home: ShellPage(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(controller.requestedTimeframes, isEmpty);

    await tester.scrollUntilVisible(
      find.text('local'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('local'));
    await tester.pumpAndSettle();
    expect(find.byType(StoragePage), findsOneWidget);
    await tester.tap(find.byKey(const Key('storage-capacity-tab')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('storage-capacity-list')), findsOneWidget);
    expect(find.text('Capacity history'), findsOneWidget);
    expect(controller.requestedTimeframes, isEmpty);

    await tester.tap(find.text('Load history'));
    await tester.pumpAndSettle();
    expect(controller.requestedTimeframes, [StorageMetricTimeframe.hour]);
    await tester.ensureVisible(find.textContaining('Latest 75.0%'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Latest 75.0%'), findsOneWidget);
    expect(find.textContaining('Usage range 50.0%–75.0%'), findsOneWidget);
    expect(find.textContaining('1 malformed ignored'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('24 hours'),
      -200,
      scrollable: find.descendant(
        of: find.byKey(const Key('storage-capacity-list')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('24 hours'));
    await tester.pumpAndSettle();
    expect(controller.requestedTimeframes, [StorageMetricTimeframe.hour]);
    expect(find.textContaining('Latest 75.0%'), findsNothing);
    await tester.tap(find.text('Load history'));
    await tester.pumpAndSettle();
    expect(controller.requestedTimeframes, [
      StorageMetricTimeframe.hour,
      StorageMetricTimeframe.day,
    ]);

    controller.active = const ConnectionProfile(
      id: 'b',
      name: 'B',
      endpoint: 'https://b.example',
    );
    controller.notifyListeners();
    await tester.pump();
    expect(find.text('Storage unavailable'), findsWidgets);
    expect(find.textContaining('Latest 75.0%'), findsNothing);
    expect(find.text('local'), findsNothing);
  });

  testWidgets('guest performance history is explicit and session redacted', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = _GuestMetricController(
      ProfileRepository(prefs, _EmptyVault()),
    );
    addTearDown(controller.dispose);
    controller.active = const ConnectionProfile(
      id: 'a',
      name: 'A',
      endpoint: 'https://a.example',
    );
    controller.inventory = Inventory.fromResources([
      {
        'type': 'qemu',
        'node': 'pve1',
        'vmid': 101,
        'name': 'Web',
        'status': 'running',
      },
    ]);
    final guest = controller.inventory!.guests.single;
    await tester.pumpWidget(
      MaterialApp(
        home: GuestPage(
          controller: controller,
          guest: guest,
          profileId: 'a',
          generation: controller.connectionGeneration,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('guest-metrics-tab')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guest-metrics-list')), findsOneWidget);
    expect(controller.requestedTimeframes, isEmpty);

    await tester.tap(find.text('Load history'));
    await tester.pumpAndSettle();
    expect(controller.requestedTimeframes, [GuestMetricTimeframe.hour]);
    expect(find.textContaining('Latest 30.0%'), findsOneWidget);
    expect(find.textContaining('Range 10.0%–30.0%'), findsOneWidget);
    expect(find.textContaining('1 malformed ignored'), findsOneWidget);

    await tester.tap(find.text('24 hours'));
    await tester.pumpAndSettle();
    expect(controller.requestedTimeframes, [GuestMetricTimeframe.hour]);
    expect(find.textContaining('Latest 30.0%'), findsNothing);
    await tester.tap(find.text('Load history'));
    await tester.pumpAndSettle();
    expect(controller.requestedTimeframes, [
      GuestMetricTimeframe.hour,
      GuestMetricTimeframe.day,
    ]);

    controller.active = const ConnectionProfile(
      id: 'b',
      name: 'B',
      endpoint: 'https://b.example',
    );
    controller.notifyListeners();
    await tester.pump();
    expect(find.textContaining('Latest 30.0%'), findsNothing);
    expect(find.text('Web'), findsNothing);
    expect(find.text('Guest unavailable'), findsOneWidget);
  });

  testWidgets(
    'guest configuration is on-demand allowlisted and session redacted',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = _GuestConfigurationController(
        ProfileRepository(prefs, _EmptyVault()),
      );
      addTearDown(controller.dispose);
      controller.active = const ConnectionProfile(
        id: 'a',
        name: 'A',
        endpoint: 'https://a.example',
      );
      controller.inventory = Inventory.fromResources([
        {
          'type': 'qemu',
          'node': 'pve1',
          'vmid': 101,
          'name': 'Web',
          'status': 'running',
        },
      ]);
      final guest = controller.inventory!.guests.single;
      await tester.pumpWidget(
        MaterialApp(
          home: GuestPage(
            controller: controller,
            guest: guest,
            profileId: 'a',
            generation: controller.connectionGeneration,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('guest-configuration-tab')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('guest-configuration-list')), findsOneWidget);
      expect(controller.requestedVmids, isEmpty);
      expect(find.text('CPU cores'), findsNothing);

      await tester.tap(find.byKey(const Key('guest-load-configuration')));
      await tester.pumpAndSettle();
      expect(controller.requestedVmids, [101]);
      expect(find.text('CPU cores'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.textContaining('2 withheld/unsupported'), findsOneWidget);
      expect(find.textContaining('must-not-render'), findsNothing);

      final configurationScroll = find.descendant(
        of: find.byKey(const Key('guest-configuration-list')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('Storage'),
        200,
        scrollable: configurationScroll,
      );
      expect(find.text('Storage'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Network'),
        200,
        scrollable: configurationScroll,
      );
      expect(find.text('Network'), findsOneWidget);

      controller.inventory = Inventory.fromResources([]);
      controller.notifyListeners();
      await tester.pump();
      expect(find.text('CPU cores'), findsNothing);
      expect(find.text('local-lvm:vm-101-disk-0,size=64G'), findsNothing);

      controller.active = const ConnectionProfile(
        id: 'b',
        name: 'B',
        endpoint: 'https://b.example',
      );
      controller.notifyListeners();
      await tester.pump();
      expect(find.text('Web'), findsNothing);
      expect(find.text('Guest unavailable'), findsOneWidget);
    },
  );

  testWidgets('guest access hints are on-demand and session redacted', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = _GuestPermissionController(
      ProfileRepository(prefs, _EmptyVault()),
    );
    addTearDown(controller.dispose);
    controller.active = const ConnectionProfile(
      id: 'a',
      name: 'A',
      endpoint: 'https://a.example',
    );
    controller.inventory = Inventory.fromResources([
      {
        'type': 'qemu',
        'node': 'pve1',
        'vmid': 101,
        'name': 'Web',
        'status': 'running',
      },
    ]);
    final guest = controller.inventory!.guests.single;
    await tester.pumpWidget(
      MaterialApp(
        home: GuestPage(
          controller: controller,
          guest: guest,
          profileId: 'a',
          generation: controller.connectionGeneration,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('guest-access-tab')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guest-access-list')), findsOneWidget);
    expect(controller.requestedVmids, isEmpty);
    expect(find.text('Power controls'), findsNothing);

    await tester.tap(find.byKey(const Key('guest-load-permissions')));
    await tester.pumpAndSettle();
    expect(controller.requestedVmids, [101]);
    expect(find.text('Power controls'), findsOneWidget);
    expect(find.text('VM.PowerMgmt'), findsOneWidget);
    expect(find.textContaining('1 malformed ignored'), findsOneWidget);

    final accessScroll = find.descendant(
      of: find.byKey(const Key('guest-access-list')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('Configure disks'),
      200,
      scrollable: accessScroll,
    );
    expect(find.text('Configure disks'), findsOneWidget);

    controller.inventory = Inventory.fromResources([]);
    controller.notifyListeners();
    await tester.pump();
    expect(find.text('Power controls'), findsNothing);

    controller.active = const ConnectionProfile(
      id: 'b',
      name: 'B',
      endpoint: 'https://b.example',
    );
    controller.notifyListeners();
    await tester.pump();
    expect(find.text('Web'), findsNothing);
    expect(find.text('Guest unavailable'), findsOneWidget);
  });

  testWidgets(
    'guest recovery tab loads snapshots and scopes recent backup tasks',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = _GuestSnapshotController(
        ProfileRepository(prefs, _EmptyVault()),
      );
      addTearDown(controller.dispose);
      controller.active = const ConnectionProfile(
        id: 'a',
        name: 'A',
        endpoint: 'https://a.example',
      );
      controller.inventory = Inventory.fromResources([
        {
          'type': 'qemu',
          'node': 'pve1',
          'vmid': 101,
          'name': 'Web',
          'status': 'running',
        },
      ]);
      controller.storages = const [
        StoragePool(
          node: 'pve1',
          id: 'backup',
          type: 'dir',
          enabled: true,
          active: true,
          contentTypes: ['backup'],
        ),
      ];
      controller.serverTasks = const [
        RecentServerTask(
          upid: 'UPID:pve1:1:2:3:vzdump:101:user@pve:',
          node: 'pve1',
          operation: 'vzdump',
          resourceId: '101',
          status: 'stopped',
          exitStatus: 'OK',
        ),
        RecentServerTask(
          upid: 'UPID:pve1:4:5:6:vzdump:202:user@pve:',
          node: 'pve1',
          operation: 'vzdump',
          resourceId: '202',
          status: 'stopped',
          exitStatus: 'OK',
        ),
      ];
      final guest = controller.inventory!.guests.single;
      await tester.pumpWidget(
        MaterialApp(
          home: GuestPage(
            controller: controller,
            guest: guest,
            profileId: 'a',
            generation: controller.connectionGeneration,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('guest-recovery-tab')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('guest-recovery-list')), findsOneWidget);
      expect(controller.requestedVmids, isEmpty);
      expect(controller.requestedBackupStorages, isEmpty);
      final recoveryScroll = find.descendant(
        of: find.byKey(const Key('guest-recovery-list')),
        matching: find.byType(Scrollable),
      );

      await tester.scrollUntilVisible(
        find.byKey(const Key('guest-backup-validation-confidence')),
        260,
        scrollable: recoveryScroll,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('guest-backup-validation-headline')),
        findsOneWidget,
      );
      expect(find.text('Not assessed'), findsOneWidget);
      expect(
        find.textContaining('No PBS verification result'),
        findsOneWidget,
      );

      await tester.scrollUntilVisible(
        find.text('Recent backup tasks'),
        260,
        scrollable: recoveryScroll,
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('does not by itself prove a matching archive'),
        findsOneWidget,
      );
      expect(find.text('Backup task • succeeded'), findsOneWidget);
      expect(find.textContaining('202'), findsNothing);

      await tester.scrollUntilVisible(
        find.byKey(const Key('guest-load-backup-archives')),
        -260,
        scrollable: recoveryScroll,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('guest-load-backup-archives')));
      await tester.pumpAndSettle();
      expect(controller.requestedBackupStorages, ['backup']);
      await tester.scrollUntilVisible(
        find.textContaining('Latest • vzdump-qemu-101-2026_11_11'),
        220,
        scrollable: recoveryScroll,
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Latest • vzdump-qemu-101-2026_11_11'),
        findsOneWidget,
      );
      expect(find.textContaining('1 unusable row(s) ignored'), findsOneWidget);
      expect(
        find.textContaining('Archive visibility is not a checksum'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('guest-backup-validation-confidence')),
        220,
        scrollable: recoveryScroll,
      );
      await tester.pumpAndSettle();
      expect(find.text('Partial evidence'), findsOneWidget);
      expect(
        find.textContaining('exact QEMU 101 identity'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Latest visible task: succeeded'),
        findsOneWidget,
      );
      expect(
        find.textContaining('never authorizes restore'),
        findsOneWidget,
      );

      await tester.scrollUntilVisible(
        find.byKey(const Key('guest-load-snapshots')),
        -260,
        scrollable: recoveryScroll,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('guest-load-snapshots')));
      await tester.pumpAndSettle();
      expect(controller.requestedVmids, [101]);
      await tester.scrollUntilVisible(
        find.textContaining('1 malformed ignored'),
        160,
        scrollable: recoveryScroll,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('1 malformed ignored'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Current state'),
        120,
        scrollable: recoveryScroll,
      );
      await tester.pumpAndSettle();
      expect(find.text('Current state'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('before-upgrade'),
        120,
        scrollable: recoveryScroll,
      );
      await tester.pumpAndSettle();
      expect(find.text('before-upgrade'), findsOneWidget);
      expect(find.textContaining('Includes VM memory state'), findsOneWidget);

      controller.inventory = Inventory.fromResources([]);
      controller.notifyListeners();
      await tester.pump();
      expect(find.text('before-upgrade'), findsNothing);
      expect(find.textContaining('Latest • vzdump-qemu-101'), findsNothing);

      controller.active = const ConnectionProfile(
        id: 'b',
        name: 'B',
        endpoint: 'https://b.example',
      );
      controller.notifyListeners();
      await tester.pump();
      expect(find.text('before-upgrade'), findsNothing);
      expect(find.text('Web'), findsNothing);
      expect(find.text('Guest unavailable'), findsOneWidget);
    },
  );

  testWidgets('task details open on demand and redact on profile switch', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = _TaskInspectionController(
      ProfileRepository(prefs, _EmptyVault()),
    );
    addTearDown(controller.dispose);
    controller.active = const ConnectionProfile(
      id: 'a',
      name: 'A',
      endpoint: 'https://a.example',
    );
    controller.serverTasks = const [
      RecentServerTask(
        node: 'pve1',
        upid: 'UPID:pve1:1:2:3:qmstart:101:user@pve:',
        operation: 'qmstart',
        resourceId: '101',
        status: 'stopped',
        exitStatus: 'OK',
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(home: ShellPage(controller: controller)),
    );
    await tester.tap(find.text('Tasks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start VM • 101'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDetailsPage), findsOneWidget);
    expect(find.textContaining('Read-only log entry'), findsOneWidget);
    expect(find.text('Succeeded'), findsOneWidget);
    controller.active = const ConnectionProfile(
      id: 'b',
      name: 'B',
      endpoint: 'https://b.example',
    );
    controller.notifyListeners();
    await tester.pump();
    expect(find.textContaining('Read-only log entry'), findsNothing);
    expect(find.textContaining('Connection changed.'), findsOneWidget);
  });

  testWidgets('task log pages and refresh remain explicit bounded reads', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = _TaskInspectionController(
      ProfileRepository(prefs, _EmptyVault()),
    );
    addTearDown(controller.dispose);
    controller.active = const ConnectionProfile(
      id: 'a',
      name: 'A',
      endpoint: 'https://a.example',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TaskDetailsPage(
          controller: controller,
          profileId: 'a',
          generation: controller.connectionGeneration,
          node: 'pve1',
          upid: 'UPID:pve1:1:2:3:qmstart:101:user@pve:',
          title: 'Task',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.requestedStarts, [0]);
    expect(find.textContaining('Read-only log entry 0'), findsOneWidget);
    await tester.tap(find.text('Next 100'));
    await tester.pumpAndSettle();
    expect(controller.requestedStarts, [0, 100]);
    expect(find.textContaining('Read-only log entry 100'), findsOneWidget);
    expect(find.text('Next 100'), findsNothing);
    await tester.tap(find.text('Refresh status and log'));
    await tester.pumpAndSettle();
    expect(controller.requestedStarts, [0, 100, 100]);
    await tester.tap(find.text('Previous 100'));
    await tester.pumpAndSettle();
    expect(controller.requestedStarts, [0, 100, 100, 0]);
    controller.active = const ConnectionProfile(
      id: 'b',
      name: 'B',
      endpoint: 'https://b.example',
    );
    controller.notifyListeners();
    await tester.pump();
    expect(find.textContaining('Read-only log entry'), findsNothing);
    expect(find.textContaining('Connection changed.'), findsOneWidget);
  });

  testWidgets(
    'incident inbox shows retained signals and safe task drill-down',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = _TaskInspectionController(
        ProfileRepository(prefs, _EmptyVault()),
      );
      addTearDown(controller.dispose);
      controller.active = const ConnectionProfile(
        id: 'a',
        name: 'A',
        endpoint: 'https://a.example',
      );
      controller.inventory = Inventory.fromResources([
        {'type': 'node', 'node': 'pve1', 'status': 'offline'},
      ]);
      controller.serverTasks = const [
        RecentServerTask(
          node: 'pve1',
          upid: 'UPID:pve1:1:2:3:vzshutdown:202:user@pve:',
          operation: 'vzshutdown',
          resourceId: '202',
          status: 'stopped',
          exitStatus: 'failed',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(home: ShellPage(controller: controller)),
      );
      expect(find.text('Incidents'), findsOneWidget);
      await tester.tap(find.text('Incidents'));
      await tester.pumpAndSettle();

      expect(find.text('Incident inbox'), findsOneWidget);
      expect(find.text('Node pve1 is offline'), findsOneWidget);
      expect(
        find.text('Task failed: Shut down container • 202'),
        findsOneWidget,
      );
      expect(find.textContaining('UPID:'), findsNothing);

      await tester.scrollUntilVisible(
        find.text('Task failed: Shut down container • 202'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Task failed: Shut down container • 202'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskDetailsPage), findsOneWidget);
      expect(controller.requestedStarts, [0]);

      await tester.pageBack();
      await tester.pumpAndSettle();
      controller.setDeviceNetworkState(DeviceNetworkState.unavailable);
      await tester.pumpWidget(
        MaterialApp(home: ShellPage(controller: controller)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Incidents'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('incident-stale-warning')), findsOneWidget);
      expect(find.text('Node pve1 is offline'), findsOneWidget);
    },
  );

  testWidgets('task history filters stay local and reset on profile switch', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = _TaskInspectionController(
      ProfileRepository(prefs, _EmptyVault()),
    );
    addTearDown(controller.dispose);
    controller.active = const ConnectionProfile(
      id: 'a',
      name: 'A',
      endpoint: 'https://a.example',
    );
    controller.serverTasks = const [
      RecentServerTask(
        node: 'pve1',
        upid: 'UPID:pve1:1:2:3:qmstart:101:user@pve:',
        operation: 'qmstart',
        resourceId: '101',
        status: 'stopped',
        exitStatus: 'OK',
      ),
      RecentServerTask(
        node: 'pve2',
        upid: 'UPID:pve2:1:2:3:vzshutdown:202:user@pve:',
        operation: 'vzshutdown',
        resourceId: '202',
        status: 'stopped',
        exitStatus: 'failed',
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(home: ShellPage(controller: controller)),
    );
    await tester.tap(find.text('Tasks'));
    await tester.pumpAndSettle();
    expect(find.text('Start VM • 101'), findsOneWidget);
    expect(find.text('Shut down container • 202'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('task-history-search')),
      'pve2',
    );
    await tester.pumpAndSettle();
    expect(find.text('Start VM • 101'), findsNothing);
    expect(find.text('Shut down container • 202'), findsOneWidget);
    await tester.tap(find.byKey(const Key('task-state-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Succeeded').last);
    await tester.pumpAndSettle();
    expect(find.text('Shut down container • 202'), findsNothing);
    expect(find.textContaining('No recent tasks match'), findsOneWidget);

    // A different profile must never inherit another profile's task query.
    controller.active = const ConnectionProfile(
      id: 'b',
      name: 'B',
      endpoint: 'https://b.example',
    );
    await tester.pumpWidget(
      MaterialApp(home: ShellPage(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Start VM • 101'), findsOneWidget);
    expect(find.text('Shut down container • 202'), findsOneWidget);
    expect(find.textContaining('No recent tasks match'), findsNothing);
  });

  testWidgets('onboarding stages server token and verification', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = _RecordingController(
      ProfileRepository(prefs, _EmptyVault()),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: ConnectPage(controller: controller)),
    );
    expect(find.text('Your infrastructure.\nIn your hands.'), findsOneWidget);
    expect(find.text('Step 1 of 3 • Server'), findsOneWidget);
    expect(find.text('Server URL'), findsOneWidget);
    expect(find.text('API token identifier'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('connection-name')),
      'Home Lab',
    );
    await tester.enterText(
      find.byKey(const Key('connection-url')),
      'https://pve.local',
    );
    await _tapVisible(tester, find.byKey(const Key('connection-next')));
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 3 • API token'), findsOneWidget);
    expect(find.text('API token identifier'), findsOneWidget);
    expect(find.text('API token secret'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('connection-token-id')),
      'me@pve!test',
    );
    await tester.enterText(
      find.byKey(const Key('connection-token-secret')),
      'test-secret',
    );
    await _tapVisible(tester, find.byKey(const Key('connection-next')));
    await tester.pumpAndSettle();

    expect(find.text('Step 3 of 3 • Verify'), findsOneWidget);
    expect(find.text('Verify connection'), findsOneWidget);
    expect(find.text('https://pve.local:8006'), findsOneWidget);
    expect(find.byKey(const Key('connection-save')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('connection-save')))
          .onPressed,
      isNull,
    );

    await _tapVisible(tester, find.byKey(const Key('connection-test')));
    await tester.pumpAndSettle();
    expect(find.text('Connection verified'), findsOneWidget);
    expect(controller.checks, 1);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('connection-save')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'insecure connection requires confirmation before check and save',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = _RecordingController(
        ProfileRepository(prefs, _EmptyVault()),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(home: ConnectPage(controller: controller)),
      );
      await _advanceConnectionWizard(
        tester,
        address: 'https://public.example',
        toggleInsecure: true,
      );

      await _tapVisible(tester, find.byKey(const Key('connection-test')));
      await tester.pumpAndSettle();
      expect(controller.checks, 0);
      expect(
        find.textContaining('Server: https://public.example:8006'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(controller.checks, 0);

      await _tapVisible(tester, find.byKey(const Key('connection-test')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect without verification'));
      await tester.pumpAndSettle();
      expect(controller.checks, 1);
      expect(
        find.textContaining('TLS identity verification was disabled'),
        findsOneWidget,
      );

      await _tapVisible(tester, find.byKey(const Key('connection-save')));
      await tester.pumpAndSettle();
      expect(controller.connections, isEmpty);
      await tester.tap(find.text('Connect without verification'));
      await tester.pumpAndSettle();
      expect(controller.connections, [true]);
    },
  );

  testWidgets(
    'strict connection verifies and saves without TLS warning dialog',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = _RecordingController(
        ProfileRepository(prefs, _EmptyVault()),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(home: ConnectPage(controller: controller)),
      );
      await _advanceConnectionWizard(tester, address: 'https://public.example');
      await _tapVisible(tester, find.byKey(const Key('connection-test')));
      await tester.pumpAndSettle();
      expect(controller.checks, 1);
      expect(find.byType(AlertDialog), findsNothing);
      await _tapVisible(tester, find.byKey(const Key('connection-save')));
      await tester.pumpAndSettle();
      expect(controller.connections, [false]);
    },
  );

  testWidgets(
    'profile edit keeps saved token when credential step stays blank',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = _RecordingController(
        ProfileRepository(prefs, _EmptyVault()),
      );
      addTearDown(controller.dispose);
      const profile = ConnectionProfile(
        id: 'lab',
        name: 'Home Lab',
        endpoint: 'https://pve.local:8006',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ConnectPage(controller: controller, profile: profile),
        ),
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('connection-name')))
            .controller
            ?.text,
        'Home Lab',
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('connection-url')))
            .controller
            ?.text,
        'https://pve.local:8006',
      );

      await _tapVisible(tester, find.byKey(const Key('connection-next')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Leave both token fields blank'),
        findsOneWidget,
      );
      await _tapVisible(tester, find.byKey(const Key('connection-next')));
      await tester.pumpAndSettle();
      expect(
        find.text('Credential: keep encrypted saved token'),
        findsOneWidget,
      );

      await _tapVisible(tester, find.byKey(const Key('connection-test')));
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.byKey(const Key('connection-save')));
      await tester.pumpAndSettle();

      expect(controller.updates, hasLength(1));
      expect(controller.updates.single['profileId'], profile.id);
      expect(controller.updates.single['name'], profile.name);
      expect(controller.updates.single['tokenId'], '');
      expect(controller.updates.single['secret'], '');
    },
  );

  testWidgets('profile edit rejects a partial replacement token', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = _RecordingController(
      ProfileRepository(prefs, _EmptyVault()),
    );
    addTearDown(controller.dispose);
    const profile = ConnectionProfile(
      id: 'lab',
      name: 'Home Lab',
      endpoint: 'https://pve.local:8006',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ConnectPage(controller: controller, profile: profile),
      ),
    );
    await _tapVisible(tester, find.byKey(const Key('connection-next')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('connection-token-id')),
      'me@pve!new',
    );
    await _tapVisible(tester, find.byKey(const Key('connection-next')));
    await tester.pump();

    expect(controller.updates, isEmpty);
    expect(controller.checks, 0);
    expect(find.text('Enter the secret or clear the token ID'), findsOneWidget);
  });

  testWidgets('add-connection route cannot pop while final save is running', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = _BlockingController(
      ProfileRepository(prefs, _EmptyVault()),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ConnectPage(controller: controller),
                ),
              ),
              child: const Text('Open connection form'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open connection form'));
    await tester.pumpAndSettle();
    await _advanceConnectionWizard(tester);
    await _tapVisible(tester, find.byKey(const Key('connection-test')));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byKey(const Key('connection-save')));
    await tester.pump();
    await controller.started.future;

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(ConnectPage), findsOneWidget);

    controller.gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(ConnectPage), findsNothing);
  });

  testWidgets('connection-check exceptions are never displayed verbatim', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = _RecordingController(
      ProfileRepository(prefs, _EmptyVault()),
    )..connectionError = StateError('sensitive-test-marker');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: ConnectPage(controller: controller)),
    );
    await _advanceConnectionWizard(tester);
    await _tapVisible(tester, find.byKey(const Key('connection-test')));
    await tester.pumpAndSettle();
    expect(find.textContaining('sensitive-test-marker'), findsNothing);
    expect(find.textContaining('Could not save or open'), findsOneWidget);
  });

  testWidgets(
    'Guests exposes the constrained QEMU create wizard from live inventory',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = AppController(
        repository: ProfileRepository(prefs, _EmptyVault()),
      );
      addTearDown(controller.dispose);
      controller.active = const ConnectionProfile(
        id: 'lab',
        name: 'Lab',
        endpoint: 'https://pve.local',
      );
      controller.inventory = Inventory.fromResources([
        {'type': 'node', 'node': 'pve1', 'status': 'online'},
        {
          'type': 'qemu',
          'node': 'pve1',
          'vmid': 101,
          'name': 'Existing VM',
          'status': 'stopped',
        },
      ]);

      await tester.pumpWidget(
        MaterialApp(home: ShellPage(controller: controller)),
      );
      await tester.tap(find.text('Guests'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('guest-create-qemu')), findsOneWidget);
      await tester.tap(find.byKey(const Key('guest-create-qemu')));
      await tester.pumpAndSettle();

      expect(find.text('Create QEMU VM'), findsOneWidget);
      expect(find.text('Empty VM shell'), findsOneWidget);
      expect(find.byKey(const Key('qemu-create-node')), findsOneWidget);
      expect(find.byKey(const Key('qemu-create-vmid')), findsOneWidget);
      expect(find.byKey(const Key('qemu-create-name')), findsOneWidget);
      expect(find.byKey(const Key('qemu-create-cores')), findsOneWidget);
      expect(find.byKey(const Key('qemu-create-memory')), findsOneWidget);
      expect(find.textContaining('Storage, networking, media'), findsOneWidget);
      final createScroll = find
          .descendant(
            of: find.byKey(const Key('qemu-create-list')),
            matching: find.byType(Scrollable),
          )
          .first;
      expect(createScroll, findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('qemu-create-onboot')),
        260,
        scrollable: createScroll,
      );
      expect(find.byKey(const Key('qemu-create-onboot')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Safety boundary'),
        260,
        scrollable: createScroll,
      );
      expect(find.text('Safety boundary'), findsOneWidget);
    },
  );

  testWidgets(
    'template discovery exposes guarded clone instead of power actions',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = AppController(
        repository: ProfileRepository(prefs, _EmptyVault()),
      );
      addTearDown(controller.dispose);
      controller.active = const ConnectionProfile(
        id: 'lab',
        name: 'Lab',
        endpoint: 'https://pve.local',
      );
      controller.inventory = Inventory.fromResources([
        {'type': 'node', 'node': 'pve1', 'status': 'online'},
        {
          'type': 'qemu',
          'node': 'pve1',
          'vmid': 900,
          'name': 'Ubuntu template',
          'status': 'stopped',
          'template': 1,
        },
      ]);

      await tester.pumpWidget(
        MaterialApp(home: ShellPage(controller: controller)),
      );
      await tester.tap(find.text('Guests'));
      await tester.pumpAndSettle();

      expect(find.text('Templates'), findsOneWidget);
      expect(
        find.textContaining('TEMPLATE • QEMU • 900 • pve1'),
        findsOneWidget,
      );
      await tester.tap(find.text('Templates'));
      await tester.pumpAndSettle();
      expect(find.text('1 templates'), findsOneWidget);

      await tester.tap(find.text('Ubuntu template'));
      await tester.pumpAndSettle();
      expect(find.text('Template'), findsOneWidget);
      expect(
        find.text(
          'Template power actions are unavailable. Use the reviewed clone wizard for a full same-node clone.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('guest-primary-action')), findsNothing);
      final clone = tester.widget<FilledButton>(
        find.byKey(const Key('guest-clone-template')),
      );
      expect(clone.onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('guest-clone-template')));
      await tester.pumpAndSettle();
      expect(find.text('Clone template'), findsOneWidget);
      expect(find.text('Full same-node clone'), findsOneWidget);
      expect(find.byKey(const Key('clone-vmid-field')), findsOneWidget);
      expect(find.byKey(const Key('clone-name-field')), findsOneWidget);
      expect(find.text('Safety preflight'), findsOneWidget);
    },
  );

  testWidgets(
    'guest navigation captures the profile before building the route',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = AppController(
        repository: ProfileRepository(prefs, _EmptyVault()),
      );
      addTearDown(controller.dispose);
      const a = ConnectionProfile(
        id: 'a',
        name: 'A',
        endpoint: 'https://a.example',
      );
      const b = ConnectionProfile(
        id: 'b',
        name: 'B',
        endpoint: 'https://b.example',
      );
      controller.active = a;
      controller.inventory = Inventory.fromResources([
        {
          'type': 'qemu',
          'vmid': 101,
          'node': 'pve1',
          'name': 'Web',
          'status': 'running',
        },
      ]);
      await tester.pumpWidget(
        MaterialApp(home: ShellPage(controller: controller)),
      );
      await tester.tap(find.text('Guests'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Web'));
      controller.active = b;
      await tester.pumpAndSettle();
      expect(tester.widget<GuestPage>(find.byType(GuestPage)).profileId, a.id);
    },
  );

  testWidgets('shell opens dedicated connection manager with metadata', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = _RecordingController(
      ProfileRepository(prefs, _EmptyVault()),
    );
    addTearDown(controller.dispose);
    const profile = ConnectionProfile(
      id: 'lab',
      name: 'Lab',
      endpoint: 'https://pve.local:8006',
      lastServerVersion: '9.2.4',
    );
    controller.active = profile;
    controller.profiles = const [profile];

    await tester.pumpWidget(
      MaterialApp(home: ShellPage(controller: controller)),
    );

    expect(find.textContaining('PVE 9.2.4'), findsOneWidget);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('manage-connections')), findsOneWidget);
    expect(find.textContaining('PVE 9.2.4 (last observed)'), findsNothing);

    await tester.tap(find.byKey(const Key('manage-connections')));
    await tester.pumpAndSettle();
    expect(find.byType(ConnectionsPage), findsOneWidget);
    expect(find.text('PVE 9.2.4 • last observed'), findsOneWidget);
    expect(find.text('TLS verification on'), findsOneWidget);

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('connection-test-lab')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Connection verified'), findsOneWidget);
    expect(controller.checks, 1);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
  });

  testWidgets('saved insecure connection test requires confirmation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = _RecordingController(
      ProfileRepository(prefs, _EmptyVault()),
    );
    addTearDown(controller.dispose);
    const profile = ConnectionProfile(
      id: 'lab',
      name: 'Lab',
      endpoint: 'https://pve.local:8006',
      allowInvalidCertificates: true,
      lastServerVersion: '9.2.4',
    );
    controller.active = profile;
    controller.profiles = const [profile];

    await tester.pumpWidget(
      MaterialApp(home: ConnectionsPage(controller: controller)),
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('connection-test-lab')),
    );
    await tester.pumpAndSettle();

    expect(controller.checks, 0);
    expect(find.text('Test without certificate verification?'), findsOneWidget);
    expect(
      find.textContaining('Server: https://pve.local:8006'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.checks, 0);

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('connection-test-lab')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test without verification'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(controller.checks, 1);
    expect(find.text('Connection verified'), findsOneWidget);
    expect(
      find.textContaining('TLS identity verification was disabled'),
      findsOneWidget,
    );
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'connection manager fits a narrow phone at 200 percent text scale',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = _RecordingController(
        ProfileRepository(prefs, _EmptyVault()),
      );
      addTearDown(controller.dispose);
      const profile = ConnectionProfile(
        id: 'lab',
        name: 'A very long saved connection display name',
        endpoint: 'https://pve-long-hostname.example:8006',
        allowInvalidCertificates: true,
        lastServerVersion: '9.2.4',
      );
      controller.active = profile;
      controller.profiles = const [profile];
      controller.message =
          'Authentication needs attention before live inventory can be trusted.';

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: ConnectionsPage(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Connections'), findsOneWidget);
      expect(find.text('TLS UNVERIFIED'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('all shell tabs fit a narrow phone at 200 percent text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = AppController(
      repository: ProfileRepository(prefs, _EmptyVault()),
    );
    addTearDown(controller.dispose);
    controller.active = const ConnectionProfile(
      id: 'lab',
      name: 'Lab',
      endpoint: 'https://pve.local',
      allowInvalidCertificates: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: ShellPage(controller: controller),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    for (final tab in ['Guests', 'Tasks', 'Settings']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$tab must not overflow');
      if (tab == 'Guests') {
        await tester.tap(find.byKey(const Key('guest-filter-button')));
        await tester.pumpAndSettle();
        expect(find.text('Filter guests'), findsOneWidget);
        expect(find.byKey(const Key('guest-filter-apply')), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: 'guest filter sheet must not overflow at large text',
        );
        await tester.ensureVisible(find.byKey(const Key('guest-filter-apply')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('guest-filter-apply')).hitTestable(),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('guest-filter-apply')));
        await tester.pumpAndSettle();
        expect(find.text('Filter guests'), findsNothing);
      }
    }
  });

  testWidgets(
    'guest detail tabs and actions fit a narrow phone at 200 percent text scale',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = AppController(
        repository: ProfileRepository(prefs, _EmptyVault()),
      );
      addTearDown(controller.dispose);
      controller.active = const ConnectionProfile(
        id: 'lab',
        name: 'Lab',
        endpoint: 'https://pve.local',
      );
      controller.inventory = Inventory.fromResources([
        {
          'type': 'qemu',
          'node': 'pve1',
          'vmid': 101,
          'name': 'A very long guest display name',
          'status': 'running',
        },
      ]);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: GuestPage(
            controller: controller,
            guest: controller.inventory!.guests.single,
            profileId: 'lab',
            generation: controller.connectionGeneration,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      controller.setDeviceNetworkState(DeviceNetworkState.unavailable);
      await tester.pumpAndSettle();
      final guard = tester.widget<Text>(
        find.text(
          'STALE / OFFLINE — actions are disabled until a fresh refresh.',
        ),
      );
      expect(guard.maxLines, isNull);
      expect(guard.overflow, isNull);
      expect(tester.takeException(), isNull);
      for (final tab in [
        'Configuration',
        'Metrics',
        'I/O',
        'Recovery',
        'Overview',
      ]) {
        await tester.ensureVisible(find.text(tab));
        await tester.pumpAndSettle();
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '$tab must not overflow',
        );
      }
    },
  );

  testWidgets(
    'insecure profiles retain contextual labels without persistent banners',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = AppController(
        repository: ProfileRepository(prefs, _EmptyVault()),
      );
      addTearDown(controller.dispose);
      controller.active = const ConnectionProfile(
        id: 'lab',
        name: 'Lab',
        endpoint: 'https://pve.local:8006',
        allowInvalidCertificates: true,
      );
      await tester.pumpWidget(
        MaterialApp(home: ShellPage(controller: controller)),
      );
      expect(find.textContaining('TLS UNVERIFIED'), findsWidgets);
      final tlsContext = tester.widget<Text>(
        find.textContaining('TLS UNVERIFIED').first,
      );
      expect(tlsContext.data, startsWith('TLS UNVERIFIED • Lab'));
      expect(
        find.text('INSECURE: certificate verification disabled.'),
        findsNothing,
      );
      await tester.tap(find.text('Guests'));
      await tester.pumpAndSettle();
      expect(
        find.text('INSECURE: certificate verification disabled.'),
        findsNothing,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: GuestPage(
            controller: controller,
            guest: const Guest(
              node: 'pve1',
              vmid: 101,
              kind: 'qemu',
              name: 'Web',
              status: 'running',
            ),
            profileId: 'lab',
            generation: controller.connectionGeneration,
          ),
        ),
      );
      expect(
        find.text('INSECURE: certificate verification disabled.'),
        findsNothing,
      );
      controller.active = const ConnectionProfile(
        id: 'strict',
        name: 'Strict',
        endpoint: 'https://pve.local:8006',
      );
      await tester.pumpWidget(
        MaterialApp(home: ShellPage(controller: controller)),
      );
      expect(find.textContaining('TLS UNVERIFIED'), findsNothing);
    },
  );

  testWidgets(
    'guest I/O counters show totals and redact after a profile switch',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = AppController(
        repository: ProfileRepository(prefs, _EmptyVault()),
      );
      addTearDown(controller.dispose);
      controller.active = const ConnectionProfile(
        id: 'a',
        name: 'A',
        endpoint: 'https://a.example',
      );
      controller.inventory = Inventory.fromResources([
        {
          'type': 'qemu',
          'node': 'pve1',
          'vmid': 101,
          'name': 'Web',
          'status': 'running',
          'netin': 1048576,
          'netout': 0,
          'diskread': 1073741824,
        },
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: GuestPage(
            controller: controller,
            guest: controller.inventory!.guests.single,
            profileId: 'a',
            generation: controller.connectionGeneration,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('guest-io-tab')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Guest I/O counters'));
      await tester.pumpAndSettle();

      expect(find.text('Guest I/O counters'), findsOneWidget);
      expect(find.text('Network traffic'), findsOneWidget);
      expect(find.textContaining('Received: 1.0 MiB'), findsOneWidget);
      expect(find.textContaining('Sent: 0 B'), findsOneWidget);
      expect(find.textContaining('Read: 1.0 GiB'), findsOneWidget);
      expect(find.textContaining('Written: —'), findsOneWidget);
      expect(find.textContaining('not live transfer rates'), findsOneWidget);

      controller.active = const ConnectionProfile(
        id: 'b',
        name: 'B',
        endpoint: 'https://b.example',
      );
      controller.notifyListeners();
      await tester.pump();
      expect(find.textContaining('Received: 1.0 MiB'), findsNothing);
      expect(find.textContaining('Read: 1.0 GiB'), findsNothing);
      expect(find.text('Web'), findsNothing);
      expect(find.textContaining('VMID 101'), findsNothing);
      expect(find.text('Guest unavailable'), findsOneWidget);
    },
  );

  testWidgets('guest confirmation redacts when same profile reconnects', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = AppController(
      repository: ProfileRepository(prefs, _EmptyVault()),
    );
    addTearDown(controller.dispose);
    const profile = ConnectionProfile(
      id: 'a',
      name: 'A',
      endpoint: 'https://a.example',
    );
    controller.active = profile;
    controller.inventory = Inventory.fromResources([
      {
        'type': 'qemu',
        'node': 'pve1',
        'vmid': 101,
        'name': 'Confidential guest',
        'status': 'running',
      },
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: GuestPage(
          controller: controller,
          guest: controller.inventory!.guests.single,
          profileId: profile.id,
          generation: controller.connectionGeneration,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final shutdownButton = find.byKey(const Key('guest-primary-action'));
    await tester.ensureVisible(shutdownButton);
    await tester.pumpAndSettle();
    await tester.tap(shutdownButton);
    await tester.pumpAndSettle();
    expect(find.text('Shut down Confidential guest?'), findsOneWidget);

    await controller.activate(profile);
    await tester.pumpAndSettle();
    expect(find.textContaining('Confidential guest'), findsNothing);
    expect(find.text('Connection changed'), findsOneWidget);
    expect(find.text('Confirm'), findsNothing);
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.text('Guest unavailable'), findsOneWidget);
    expect(find.textContaining('Confidential guest'), findsNothing);
  });

  testWidgets('guest browse filters and sorting reset on profile switch', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = AppController(
      repository: ProfileRepository(prefs, _EmptyVault()),
    );
    addTearDown(controller.dispose);
    controller.active = const ConnectionProfile(
      id: 'a',
      name: 'A',
      endpoint: 'https://a.example',
    );
    controller.inventory = Inventory.fromResources([
      {
        'type': 'qemu',
        'vmid': 101,
        'node': 'pve1',
        'name': 'Alpha',
        'status': 'running',
      },
      {
        'type': 'lxc',
        'vmid': 102,
        'node': 'pve2',
        'name': 'Beta',
        'status': 'stopped',
      },
      {
        'type': 'qemu',
        'vmid': 103,
        'node': 'pve2',
        'name': 'Gamma',
        'status': 'running',
      },
    ]);
    await tester.pumpWidget(
      MaterialApp(home: ShellPage(controller: controller)),
    );
    await tester.tap(find.text('Guests'));
    await tester.pumpAndSettle();
    expect(find.text('3 workloads'), findsOneWidget);

    await tester.tap(find.byKey(const Key('guest-filter-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Containers'));
    await tester.ensureVisible(find.byKey(const Key('guest-filter-apply')));
    await tester.tap(find.byKey(const Key('guest-filter-apply')));
    await tester.pumpAndSettle();
    expect(find.text('1 workloads'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);

    await tester.tap(find.byKey(const Key('guest-filter-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Any type'));
    await tester.ensureVisible(find.byKey(const Key('guest-filter-node-pve2')));
    await tester.tap(find.byKey(const Key('guest-filter-node-pve2')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('guest-filter-apply')));
    await tester.tap(find.byKey(const Key('guest-filter-apply')));
    await tester.pumpAndSettle();
    expect(find.text('2 workloads'), findsOneWidget);

    await tester.tap(find.byKey(const Key('guest-filter-button')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('guest-filter-sort-vmid')));
    await tester.tap(find.byKey(const Key('guest-filter-sort-vmid')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('guest-filter-apply')));
    await tester.tap(find.byKey(const Key('guest-filter-apply')));
    await tester.pumpAndSettle();
    expect(find.text('Sort: VMID'), findsOneWidget);

    controller.active = const ConnectionProfile(
      id: 'b',
      name: 'B',
      endpoint: 'https://b.example',
    );
    controller.inventory = Inventory.fromResources([
      {
        'type': 'lxc',
        'vmid': 201,
        'node': 'other-node',
        'name': 'New profile workload',
        'status': 'running',
      },
    ]);
    await tester.pumpWidget(
      MaterialApp(home: ShellPage(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 workloads'), findsOneWidget);
    expect(find.text('New profile workload'), findsOneWidget);
    expect(find.byKey(const Key('guest-filter-button')), findsOneWidget);
    expect(find.text('Sort: VMID'), findsNothing);
  });

  testWidgets('guest filters can be saved and restored as a named view', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = ProfileRepository(prefs, _EmptyVault());
    const profile = ConnectionProfile(
      id: 'lab',
      name: 'Lab',
      endpoint: 'https://pve.local:8006',
    );
    await repo.save(
      profile,
      const ApiCredentials(tokenId: 'me@pve!test', secret: 'test'),
    );
    final controller = AppController(repository: repo);
    addTearDown(controller.dispose);
    controller.active = profile;
    controller.inventory = Inventory.fromResources([
      {
        'type': 'qemu',
        'vmid': 101,
        'node': 'pve1',
        'name': 'Alpha',
        'status': 'running',
        'tags': 'prod;web',
        'pool': 'team-a',
      },
      {
        'type': 'lxc',
        'vmid': 102,
        'node': 'pve2',
        'name': 'Beta',
        'status': 'stopped',
        'tags': 'dev;cache',
        'pool': 'team-a',
      },
      {
        'type': 'lxc',
        'vmid': 103,
        'node': 'pve2',
        'name': 'Gamma',
        'status': 'running',
        'tags': 'dev',
        'pool': 'team-b',
      },
    ]);
    await tester.pumpWidget(
      MaterialApp(home: ShellPage(controller: controller)),
    );
    await tester.tap(find.text('Guests'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Beta');
    await tester.tap(find.text('Stopped'));
    await tester.tap(find.byKey(const Key('guest-filter-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Containers'));
    await tester.ensureVisible(find.byKey(const Key('guest-filter-node-pve2')));
    await tester.tap(find.byKey(const Key('guest-filter-node-pve2')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('guest-filter-tag-dev')));
    await tester.tap(find.byKey(const Key('guest-filter-tag-dev')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('guest-filter-pool-team-a')),
    );
    await tester.tap(find.byKey(const Key('guest-filter-pool-team-a')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('guest-filter-sort-vmid')));
    await tester.tap(find.byKey(const Key('guest-filter-sort-vmid')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('guest-filter-apply')));
    await tester.tap(find.byKey(const Key('guest-filter-apply')));
    await tester.pumpAndSettle();
    expect(find.text('1 workloads'), findsOneWidget);

    await tester.ensureVisible(find.text('Save view'));
    await tester.tap(find.text('Save view'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'PVE2 stopped');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('PVE2 stopped'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '');
    await tester.tap(find.text('All'));
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('3 workloads'), findsOneWidget);

    await tester.ensureVisible(find.text('PVE2 stopped'));
    await tester.tap(find.text('PVE2 stopped'));
    await tester.pumpAndSettle();
    expect(find.text('1 workloads'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Beta'), findsOneWidget);
    expect(find.text('Sort: VMID'), findsOneWidget);
    expect(find.text('Node: pve2'), findsOneWidget);
    expect(find.text('Tag: dev'), findsOneWidget);
    expect(find.text('Pool: team-a'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      'Beta',
    );
  });

  testWidgets('saved profiles without an active selection show chooser', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repository = ProfileRepository(prefs, _EmptyVault());
    const profile = ConnectionProfile(
      id: 'lab',
      name: 'Home Lab',
      endpoint: 'https://pve.local:8006',
      lastServerVersion: '9.2.4',
    );
    await repository.save(
      profile,
      const ApiCredentials(tokenId: 'me@pve!test', secret: 'test-secret'),
    );
    await repository.setActive(null);

    await tester.pumpWidget(VirtHelmApp(repository: repository));
    await tester.pumpAndSettle();

    expect(find.byType(ConnectionsPage), findsOneWidget);
    expect(find.text('Choose connection'), findsOneWidget);
    expect(find.text('Choose where to connect'), findsOneWidget);
    expect(find.text('Home Lab'), findsOneWidget);
    expect(find.byKey(const ValueKey('connection-use-lab')), findsOneWidget);
  });

  testWidgets('app applies persisted theme before connection setup', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repository = ProfileRepository(prefs, _EmptyVault());
    await repository.setThemePreference(AppThemePreference.dark);
    await tester.pumpWidget(VirtHelmApp(repository: repository));
    await tester.pumpAndSettle();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
  });

  testWidgets('app applies AMOLED, contrast and reduced motion before setup', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repository = ProfileRepository(prefs, _EmptyVault());
    await repository.setThemePreference(AppThemePreference.amoled);
    await repository.setHighContrast(true);
    await repository.setReduceMotion(true);

    await tester.pumpWidget(VirtHelmApp(repository: repository));
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(app.darkTheme?.scaffoldBackgroundColor, Colors.black);
    expect(app.themeAnimationDuration, Duration.zero);
    expect(
      MediaQuery.of(tester.element(find.byType(ConnectPage))).disableAnimations,
      isTrue,
    );
  });

  testWidgets('local settings persist and hide optional node metrics', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repository = ProfileRepository(prefs, _EmptyVault());
    final controller = AppController(repository: repository);
    addTearDown(controller.dispose);
    controller.active = const ConnectionProfile(
      id: 'lab',
      name: 'Lab',
      endpoint: 'https://pve.local:8006',
    );
    controller.inventory = Inventory.fromResources([
      {
        'type': 'node',
        'node': 'pve1',
        'status': 'online',
        'cpu': 0.1,
        'mem': 1024,
        'uptime': 3600,
      },
    ]);

    await tester.pumpWidget(
      MaterialApp(home: ShellPage(controller: controller)),
    );
    await tester.scrollUntilVisible(
      find.text('pve1'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('CPU 10.0%'), findsOneWidget);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('theme-preference')));
    await tester.tap(find.byKey(const Key('theme-preference')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark').last);
    await tester.pumpAndSettle();
    expect(repository.themePreference, AppThemePreference.dark);

    await tester.ensureVisible(
      find.byKey(const Key('high-contrast-preference')),
    );
    await tester.tap(find.byKey(const Key('high-contrast-preference')));
    await tester.pumpAndSettle();
    expect(repository.highContrast, isTrue);

    await tester.ensureVisible(
      find.byKey(const Key('reduce-motion-preference')),
    );
    await tester.tap(find.byKey(const Key('reduce-motion-preference')));
    await tester.pumpAndSettle();
    expect(repository.reduceMotion, isTrue);

    await tester.ensureVisible(find.byKey(const Key('refresh-preference')));
    await tester.tap(find.byKey(const Key('refresh-preference')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Every minute').last);
    await tester.pumpAndSettle();
    expect(
      repository.autoRefreshPreference,
      AutoRefreshPreference.every60Seconds,
    );

    await tester.ensureVisible(
      find.byKey(const Key('node-metrics-preference')),
    );
    await tester.tap(find.byKey(const Key('node-metrics-preference')));
    await tester.pumpAndSettle();
    expect(repository.showNodeMetrics, isFalse);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.textContaining('CPU 10.0%'), findsNothing);
    expect(find.text('pve1'), findsOneWidget);
  });

  testWidgets(
    'settings fit 360 393 and 412dp at 200 percent text in light and dark',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = AppController(
        repository: ProfileRepository(prefs, _EmptyVault()),
      );
      addTearDown(controller.dispose);
      controller.active = const ConnectionProfile(
        id: 'lab',
        name: 'Lab',
        endpoint: 'https://pve.local:8006',
      );
      controller.inventory = Inventory.fromResources([
        {'type': 'node', 'node': 'pve1', 'status': 'online'},
      ]);

      for (final width in const [360.0, 393.0, 412.0]) {
        for (final brightness in const [Brightness.light, Brightness.dark]) {
          tester.view.physicalSize = Size(width, 800);
          await tester.pumpWidget(
            MaterialApp(
              theme: virthelmTheme(brightness, highContrast: true),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(2)),
                child: child!,
              ),
              home: ShellPage(
                key: ValueKey('settings-$width-$brightness'),
                controller: controller,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final navigation = tester.widget<NavigationBar>(
            find.byType(NavigationBar),
          );
          navigation.onDestinationSelected?.call(4);
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.byKey(const Key('high-contrast-preference')),
            180,
            scrollable: find.descendant(
              of: find.byKey(const Key('settings-list')),
              matching: find.byType(Scrollable),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$width dp / $brightness',
          );
        }
      }
    },
  );

  testWidgets('Home labels cached counts without exposing a guest list', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = AppController(
      repository: ProfileRepository(prefs, _EmptyVault()),
    );
    addTearDown(controller.dispose);
    controller.active = const ConnectionProfile(
      id: 'cached-lab',
      name: 'Lab',
      endpoint: 'https://pve.local:8006',
    );
    controller.cachedOverview = OfflineOverview(
      fetchedAt: DateTime.now().subtract(const Duration(hours: 1)),
      totalNodes: 2,
      onlineNodes: 1,
      totalGuests: 12,
      runningGuests: 8,
      stoppedGuests: 4,
    );
    controller.message = 'Network unavailable to the server.';
    await tester.pumpWidget(
      MaterialApp(home: ShellPage(controller: controller)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('CACHED COUNTS'), findsOneWidget);
    expect(find.textContaining('Last-known counts only'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('1 / 2'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    await tester.tap(find.text('Guests'));
    await tester.pumpAndSettle();
    expect(find.text('No live data'), findsOneWidget);
    expect(find.text('Web'), findsNothing);
  });

  testWidgets(
    'Android offline signal shows a scoped status, not a TLS banner',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = AppController(
        repository: ProfileRepository(prefs, _EmptyVault()),
      );
      addTearDown(controller.dispose);
      controller.active = const ConnectionProfile(
        id: 'lab',
        name: 'Lab',
        endpoint: 'https://pve.local:8006',
        allowInvalidCertificates: true,
      );
      controller.setDeviceNetworkState(DeviceNetworkState.unavailable);
      await tester.pumpWidget(
        MaterialApp(home: ShellPage(controller: controller)),
      );
      expect(
        find.byKey(const Key('device-network-unavailable')),
        findsOneWidget,
      );
      expect(find.textContaining('TLS UNVERIFIED'), findsWidgets);
      expect(
        find.text('INSECURE: certificate verification disabled.'),
        findsNothing,
      );
      controller.setDeviceNetworkState(DeviceNetworkState.unknown);
      await tester.pumpWidget(
        MaterialApp(home: ShellPage(controller: controller)),
      );
      expect(find.byKey(const Key('device-network-unavailable')), findsNothing);
    },
  );
}
