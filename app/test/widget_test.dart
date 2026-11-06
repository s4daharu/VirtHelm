import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:virthelm/core/app_controller.dart';
import 'package:virthelm/core/app_preferences.dart';
import 'package:virthelm/core/device_connectivity.dart';
import 'package:virthelm/main.dart';
import 'package:virthelm/core/guest_list_filter.dart';
import 'package:virthelm/core/models.dart';
import 'package:virthelm/core/offline_overview.dart';
import 'package:virthelm/core/profile_repository.dart';
import 'package:virthelm/ui/connect_page.dart';
import 'package:virthelm/ui/guest_page.dart';
import 'package:virthelm/ui/node_page.dart';
import 'package:virthelm/ui/shell.dart';
import 'package:virthelm/ui/storage_page.dart';
import 'package:virthelm/ui/task_details_page.dart';

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
  Object? connectionError;

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
    await tester.scrollUntilVisible(
      find.text('Performance history'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Performance history'), findsOneWidget);
    expect(controller.requestedTimeframes, isEmpty);

    await tester.tap(find.text('Load history'));
    await tester.pumpAndSettle();
    expect(controller.requestedTimeframes, [NodeMetricTimeframe.hour]);
    await tester.scrollUntilVisible(
      find.textContaining('Latest 40.0%'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Latest 40.0%'), findsOneWidget);
    expect(find.textContaining('Range 20.0%–40.0%'), findsOneWidget);
    expect(find.textContaining('1 malformed ignored'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('24 hours'),
      -200,
      scrollable: find.byType(Scrollable).first,
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
      {
        'type': 'node',
        'node': 'pve1',
        'status': 'online',
      },
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
    await tester.scrollUntilVisible(
      find.text('Capacity history'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Capacity history'), findsOneWidget);
    expect(controller.requestedTimeframes, isEmpty);

    await tester.tap(find.text('Load history'));
    await tester.pumpAndSettle();
    expect(controller.requestedTimeframes, [StorageMetricTimeframe.hour]);
    await tester.scrollUntilVisible(
      find.textContaining('Latest 75.0%'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Latest 75.0%'), findsOneWidget);
    expect(find.textContaining('Usage range 50.0%–75.0%'), findsOneWidget);
    expect(find.textContaining('1 malformed ignored'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('24 hours'),
      -200,
      scrollable: find.byType(Scrollable).first,
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
    await tester.scrollUntilVisible(
      find.text('Performance history'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
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
    await tester.tap(find.text('View details'));
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

  testWidgets('onboarding shows HTTPS and token fields', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = AppController(
      repository: ProfileRepository(prefs, _EmptyVault()),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: ConnectPage(controller: controller)),
    );
    expect(find.text('Your infrastructure.\nIn your hands.'), findsOneWidget);
    expect(find.text('Server URL'), findsOneWidget);
    expect(find.text('API token identifier'), findsOneWidget);
    expect(find.text('API token secret'), findsOneWidget);
    expect(find.text('Connect securely'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
  });

  testWidgets('insecure connection requires confirmation before each attempt', (
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
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Lab');
    await tester.enterText(fields.at(1), 'https://public.example');
    await tester.enterText(fields.at(2), 'me@pve!test');
    await tester.enterText(fields.at(3), 'test-secret');
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Connect (insecure)'));
    await tester.tap(find.text('Connect (insecure)'));
    // The connection button's busy spinner runs while consent is pending.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.connections, isEmpty);
    expect(find.textContaining('https://public.example:8006'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.connections, isEmpty);
    await tester.tap(find.text('Connect (insecure)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Connect without verification'));
    await tester.pumpAndSettle();
    expect(controller.connections, [true]);
  });

  testWidgets('strict connection needs no insecure confirmation', (
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
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Lab');
    await tester.enterText(fields.at(1), 'https://public.example');
    await tester.enterText(fields.at(2), 'me@pve!test');
    await tester.enterText(fields.at(3), 'test-secret');
    await tester.ensureVisible(find.text('Connect securely'));
    await tester.tap(find.text('Connect securely'));
    await tester.pumpAndSettle();
    expect(controller.connections, [false]);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
    'profile edit prefills fields and keeps saved token when token fields are blank',
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

      final fields = find.byType(TextFormField);
      expect(
        tester.widget<TextFormField>(fields.at(0)).controller?.text,
        'Home Lab',
      );
      expect(
        tester.widget<TextFormField>(fields.at(1)).controller?.text,
        'https://pve.local:8006',
      );
      expect(
        tester.widget<TextFormField>(fields.at(2)).controller?.text,
        isEmpty,
      );
      expect(
        tester.widget<TextFormField>(fields.at(3)).controller?.text,
        isEmpty,
      );

      await tester.ensureVisible(find.text('Save connection'));
      await tester.tap(find.text('Save connection'));
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
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(2), 'me@pve!new');
    await tester.ensureVisible(find.text('Save connection'));
    await tester.tap(find.text('Save connection'));
    await tester.pump();

    expect(controller.updates, isEmpty);
    expect(find.text('Enter the secret or clear the token ID'), findsOneWidget);
  });

  testWidgets(
    'add-connection route cannot pop while connection check is running',
    (tester) async {
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
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Lab');
      await tester.enterText(fields.at(1), 'https://pve.local');
      await tester.enterText(fields.at(2), 'me@pve!test');
      await tester.enterText(fields.at(3), 'test-secret');
      await tester.ensureVisible(find.text('Connect securely'));
      await tester.tap(find.text('Connect securely'));
      await tester.pump();
      await controller.started.future;

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(ConnectPage), findsOneWidget);

      controller.gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(ConnectPage), findsNothing);
    },
  );

  testWidgets('credential-plugin exceptions are never displayed verbatim', (
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
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Lab');
    await tester.enterText(fields.at(1), 'https://pve.local');
    await tester.enterText(fields.at(2), 'me@pve!test');
    await tester.enterText(fields.at(3), 'test-secret');
    await tester.ensureVisible(find.text('Connect securely'));
    await tester.tap(find.text('Connect securely'));
    await tester.pumpAndSettle();
    expect(find.textContaining('sensitive-test-marker'), findsNothing);
    expect(find.textContaining('Could not save or open'), findsOneWidget);
  });

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

  testWidgets('shell and settings show last observed server version', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = AppController(
      repository: ProfileRepository(prefs, _EmptyVault()),
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
    expect(find.textContaining('PVE 9.2.4 (last observed)'), findsOneWidget);
  });

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
    }
  });

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
      await tester.scrollUntilVisible(
        find.text('Guest I/O counters'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
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
    final shutdownTile = find.widgetWithText(ListTile, 'Shut down');
    await tester.scrollUntilVisible(
      shutdownTile,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(shutdownTile);
    await tester.pumpAndSettle();
    await tester.tap(shutdownTile);
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

    await tester.tap(find.text('Containers'));
    await tester.pumpAndSettle();
    expect(find.text('1 workloads'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    await tester.tap(find.text('Any type'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('All nodes'));
    await tester.tap(find.text('All nodes'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is CheckedPopupMenuItem<String> && widget.value == 'pve2',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 workloads'), findsOneWidget);

    await tester.ensureVisible(find.text('Sort: Favorites first'));
    await tester.tap(find.text('Sort: Favorites first'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is CheckedPopupMenuItem<GuestSort> &&
            widget.value == GuestSort.vmid,
      ),
    );
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
    expect(find.text('All nodes'), findsOneWidget);
    expect(find.text('Sort: Favorites first'), findsOneWidget);
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
    await tester.tap(find.text('Containers'));
    await tester.ensureVisible(find.text('All nodes'));
    await tester.tap(find.text('All nodes'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is CheckedPopupMenuItem<String> && widget.value == 'pve2',
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('All tags'));
    await tester.tap(find.text('All tags'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is CheckedPopupMenuItem<String> && widget.value == 'dev',
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('All pools'));
    await tester.tap(find.text('All pools'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is CheckedPopupMenuItem<String> && widget.value == 'team-a',
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Sort: Favorites first'));
    await tester.tap(find.text('Sort: Favorites first'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is CheckedPopupMenuItem<GuestSort> &&
            widget.value == GuestSort.vmid,
      ),
    );
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
    await tester.tap(find.text('Any type'));
    await tester.ensureVisible(find.text('Node: pve2'));
    await tester.tap(find.text('Node: pve2'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is CheckedPopupMenuItem<String> && widget.value == '__all',
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Tag: dev'));
    await tester.tap(find.text('Tag: dev'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is CheckedPopupMenuItem<String> && widget.value == '',
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Pool: team-a'));
    await tester.tap(find.text('Pool: team-a'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is CheckedPopupMenuItem<String> && widget.value == '',
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Sort: VMID'));
    await tester.tap(find.text('Sort: VMID'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is CheckedPopupMenuItem<GuestSort> &&
            widget.value == GuestSort.favorites,
      ),
    );
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
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
    expect(find.textContaining('Last-known counts only'), findsOneWidget);
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
