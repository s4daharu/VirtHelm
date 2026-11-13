import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:virthelm/core/app_controller.dart';
import 'package:virthelm/core/models.dart';
import 'package:virthelm/core/notification_navigation.dart';
import 'package:virthelm/core/profile_repository.dart';
import 'package:virthelm/ui/shell.dart';

class _Vault implements CredentialVault {
  @override
  Future<void> store(String id, ApiCredentials credentials) async {}

  @override
  Future<ApiCredentials?> retrieve(String id) async => null;

  @override
  Future<void> remove(String id) async {}
}

class _Resolver implements IncidentNavigationTargetResolver {
  String? result;
  String? profileId;
  String? targetHash;
  List<String> incidentKeys = const [];

  @override
  Future<String?> resolveIncidentTarget({
    required String profileId,
    required String targetHash,
    required Iterable<String> incidentKeys,
  }) async {
    this.profileId = profileId;
    this.targetHash = targetHash;
    this.incidentKeys = incidentKeys.toList(growable: false);
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.s4daharu.virthelm/incident_navigation');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('Android bridge consumes an opaque pending incident target', () async {
    const targetHash =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'takePendingIncidentIntent');
          return <String, Object?>{'open': true, 'targetHash': targetHash};
        });

    const bridge = AndroidIncidentNotificationNavigation();
    final request = await bridge.takePendingIncidentIntent();
    expect(request, isNotNull);
    expect(request?.targetHash, targetHash);
  });

  test('malformed native target degrades to generic Incidents navigation', () {
    final request = IncidentNavigationRequest.fromChannel(<String, Object?>{
      'open': true,
      'targetHash': 'not-a-hash',
    });
    expect(request, isNotNull);
    expect(request?.targetHash, isNull);
    expect(
      IncidentNavigationRequest.fromChannel(<String, Object?>{'open': false}),
      isNull,
    );
  });

  test(
    'Android resolver bounds and allowlists current incident keys',
    () async {
      const targetHash =
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      MethodCall? observed;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            observed = call;
            if (call.method == 'resolveIncidentTarget') return 'node:pve-7';
            return null;
          });

      const bridge = AndroidIncidentNotificationNavigation();
      final matched = await bridge.resolveIncidentTarget(
        profileId: 'profile-alpha',
        targetHash: targetHash,
        incidentKeys: List<String>.generate(150, (index) => 'node:pve-$index'),
      );

      expect(matched, 'node:pve-7');
      expect(observed?.method, 'resolveIncidentTarget');
      final args = Map<String, Object?>.from(observed?.arguments as Map);
      expect(args['profileId'], 'profile-alpha');
      expect(args['targetHash'], targetHash);
      expect(
        List<Object?>.from(args['incidentKeys'] as List<Object?>),
        hasLength(maxIncidentNavigationCandidates),
      );
    },
  );

  test('invalid target hash fails closed before native resolution', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls++;
          return null;
        });

    expect(
      await const AndroidIncidentNotificationNavigation().resolveIncidentTarget(
        profileId: 'profile-alpha',
        targetHash: 'invalid',
        incidentKeys: const <String>['node:pve-a'],
      ),
      isNull,
    );
    expect(calls, 0);
  });

  test(
    'controller revalidates native target against current incidents',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final resolver = _Resolver()..result = 'node:pve-b';
      final controller = AppController(
        repository: ProfileRepository(prefs, _Vault()),
        incidentNavigationTargetResolver: resolver,
      );
      addTearDown(controller.dispose);
      controller.active = const ConnectionProfile(
        id: 'lab',
        name: 'Lab',
        endpoint: 'https://pve.local:8006',
      );
      controller.inventory = Inventory(
        nodes: const <Node>[
          Node(name: 'pve-a', status: 'offline'),
          Node(name: 'pve-b', status: 'offline'),
        ],
        guests: const <Guest>[],
        fetchedAt: DateTime.utc(2026, 11, 14, 12),
      );
      const targetHash =
          'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

      expect(
        await controller.resolveIncidentNavigationTarget(targetHash),
        'node:pve-b',
      );
      expect(resolver.profileId, 'lab');
      expect(resolver.targetHash, targetHash);
      expect(
        resolver.incidentKeys,
        containsAll(<String>['node:pve-a', 'node:pve-b']),
      );

      resolver.result = 'node:not-current';
      expect(
        await controller.resolveIncidentNavigationTarget(targetHash),
        isNull,
      );
    },
  );

  testWidgets(
    'pending notification request opens Incidents on shell creation',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final controller = AppController(
        repository: ProfileRepository(prefs, _Vault()),
      );
      addTearDown(controller.dispose);
      controller.active = const ConnectionProfile(
        id: 'lab',
        name: 'Lab',
        endpoint: 'https://pve.local:8006',
      );
      controller.requestIncidentCenter();

      await tester.pumpWidget(
        MaterialApp(home: ShellPage(controller: controller)),
      );

      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        3,
      );
    },
  );

  testWidgets('opaque notification target focuses one exact current incident', (
    tester,
  ) async {
      final prefs = await SharedPreferences.getInstance();
      final resolver = _Resolver()..result = 'node:pve-b';
      final controller = AppController(
        repository: ProfileRepository(prefs, _Vault()),
        incidentNavigationTargetResolver: resolver,
      );
      addTearDown(controller.dispose);
      controller.active = const ConnectionProfile(
        id: 'lab',
        name: 'Lab',
        endpoint: 'https://pve.local:8006',
      );
      controller.inventory = Inventory(
        nodes: const <Node>[
          Node(name: 'pve-a', status: 'offline'),
          Node(name: 'pve-b', status: 'offline'),
        ],
        guests: const <Guest>[],
        fetchedAt: DateTime.utc(2026, 11, 14, 12),
      );
      const targetHash =
          'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
      controller.requestIncidentCenter(
        const IncidentNavigationRequest(targetHash: targetHash),
      );

      await tester.pumpWidget(
        MaterialApp(home: ShellPage(controller: controller)),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        3,
      );
      expect(find.byKey(const Key('notification-target-focus')), findsOneWidget);
      expect(find.text('Node pve-b is offline'), findsOneWidget);
      expect(find.text('Node pve-a is offline'), findsNothing);
  });

  testWidgets(
    'consumed notification request does not reopen Incidents after shell recreation',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final controller = AppController(
        repository: ProfileRepository(prefs, _Vault()),
      );
      addTearDown(controller.dispose);
      controller.active = const ConnectionProfile(
        id: 'lab',
        name: 'Lab',
        endpoint: 'https://pve.local:8006',
      );
      controller.requestIncidentCenter();

      await tester.pumpWidget(
        MaterialApp(home: ShellPage(controller: controller)),
      );
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        3,
      );

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpWidget(
        MaterialApp(home: ShellPage(controller: controller)),
      );

      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
    },
  );

  testWidgets('warm notification request switches the existing shell', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final controller = AppController(
      repository: ProfileRepository(prefs, _Vault()),
    );
    addTearDown(controller.dispose);
    controller.active = const ConnectionProfile(
      id: 'lab',
      name: 'Lab',
      endpoint: 'https://pve.local:8006',
    );

    await tester.pumpWidget(
      MaterialApp(home: ShellPage(controller: controller)),
    );
    await tester.tap(find.text('Guests'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );

    controller.requestIncidentCenter();
    await tester.pump();

    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      3,
    );
  });
}
