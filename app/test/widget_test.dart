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
import 'package:virthelm/ui/shell.dart';
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

  @override
  Future<TaskInspection?> inspectTask({
    required String profileId,
    required int generation,
    required String node,
    required String upid,
  }) async => const TaskInspection(
    status: ServerTaskStatus(status: 'stopped', exitStatus: 'OK'),
    log: TaskLogResult(
      entries: [TaskLogEntry(number: 1, text: 'Read-only log entry')],
      malformedRecords: 0,
    ),
  );
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
      },
      {
        'type': 'lxc',
        'vmid': 102,
        'node': 'pve2',
        'name': 'Beta',
        'status': 'stopped',
      },
      {
        'type': 'lxc',
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
