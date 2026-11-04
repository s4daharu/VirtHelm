import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:virthelm/core/app_controller.dart';
import 'package:virthelm/core/models.dart';
import 'package:virthelm/core/profile_repository.dart';
import 'package:virthelm/ui/connect_page.dart';
import 'package:virthelm/ui/guest_page.dart';
import 'package:virthelm/ui/shell.dart';
import 'package:virthelm/ui/tls_warning.dart';

class _EmptyVault implements CredentialVault {
  @override
  Future<void> store(String id, ApiCredentials credentials) async {}
  @override
  Future<ApiCredentials?> retrieve(String id) async => null;
  @override
  Future<void> remove(String id) async {}
}

class _RecordingController extends AppController {
  _RecordingController(ProfileRepository repository)
    : super(repository: repository);

  final List<bool> connections = [];
  Object? connectionError;

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

  testWidgets('shell and guest screens warn for insecure profiles only', (
    tester,
  ) async {
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
    expect(find.byType(TlsWarning), findsOneWidget);
    await tester.tap(find.text('Guests'));
    await tester.pumpAndSettle();
    expect(find.byType(TlsWarning), findsOneWidget);
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
    expect(find.byType(TlsWarning), findsOneWidget);
    controller.active = const ConnectionProfile(
      id: 'strict',
      name: 'Strict',
      endpoint: 'https://pve.local:8006',
    );
    await tester.pumpWidget(
      MaterialApp(home: ShellPage(controller: controller)),
    );
    expect(find.byType(TlsWarning), findsNothing);
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

    await tester.tap(find.text('All nodes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('pve2').last);
    await tester.pumpAndSettle();
    expect(find.text('2 workloads'), findsOneWidget);

    await tester.tap(find.text('Sort: Favorites first'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('VMID'));
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
    await tester.tap(find.text('All nodes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('pve2').last);
    await tester.tap(find.text('Sort: Favorites first'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('VMID'));
    await tester.pumpAndSettle();
    expect(find.text('1 workloads'), findsOneWidget);

    await tester.tap(find.text('Save view'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      'PVE2 stopped',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('PVE2 stopped'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '');
    await tester.tap(find.text('All'));
    await tester.tap(find.text('Any type'));
    await tester.tap(find.text('Node: pve2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All nodes').last);
    await tester.tap(find.text('Sort: VMID'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Favorites first'));
    await tester.pumpAndSettle();
    expect(find.text('3 workloads'), findsOneWidget);

    await tester.tap(find.text('PVE2 stopped'));
    await tester.pumpAndSettle();
    expect(find.text('1 workloads'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Sort: VMID'), findsOneWidget);
    expect(find.text('Node: pve2'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      'Beta',
    );
  });
}
