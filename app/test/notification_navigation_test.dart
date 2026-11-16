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
  List<IncidentNavigationCandidate> candidates = const [];

  @override
  Future<String?> resolveIncidentTarget({
    required String profileId,
    required String targetHash,
    required Iterable<IncidentNavigationCandidate> candidates,
  }) async {
    this.profileId = profileId;
    this.targetHash = targetHash;
    this.candidates = candidates.toList(growable: false);
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
    'Android resolver bounds and allowlists current incident candidates',
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
        candidates: List<IncidentNavigationCandidate>.generate(
          150,
          (index) => IncidentNavigationCandidate(
            key: 'node:pve-$index',
            source: 'node',
            identity: 'pve-$index',
          ),
        ),
      );

      expect(matched, 'node:pve-7');
      expect(observed?.method, 'resolveIncidentTarget');
      final args = Map<String, Object?>.from(observed?.arguments as Map);
      expect(args['profileId'], 'profile-alpha');
      expect(args['targetHash'], targetHash);
      final candidates = List<Object?>.from(
        args['candidates'] as List<Object?>,
      );
      expect(candidates, hasLength(maxIncidentNavigationCandidates));
      expect(
        Map<String, Object?>.from(candidates.first as Map),
        <String, Object?>{
          'key': 'node:pve-0',
          'source': 'node',
          'identity': 'pve-0',
        },
      );
    },
  );

  test(
    'malformed scheduled identities fail closed before native resolution',
    () async {
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls++;
            return null;
          });

      expect(
        await const AndroidIncidentNotificationNavigation().resolveIncidentTarget(
          profileId: 'profile-alpha',
          targetHash:
              'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
          candidates: const <IncidentNavigationCandidate>[
            IncidentNavigationCandidate(
              key: 'node:pve-a',
              source: 'unsupported',
              identity: 'pve-a',
            ),
            IncidentNavigationCandidate(
              key: 'node:pve-b',
              source: 'node',
              identity: '',
            ),
          ],
        ),
        isNull,
      );
      expect(calls, 0);
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
        candidates: const <IncidentNavigationCandidate>[
          IncidentNavigationCandidate(
            key: 'node:pve-a',
            source: 'node',
            identity: 'pve-a',
          ),
        ],
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
        resolver.candidates.map((candidate) => candidate.key),
        containsAll(<String>['node:pve-a', 'node:pve-b']),
      );
      final nodeBCandidate = resolver.candidates.firstWhere(
        (candidate) => candidate.key == 'node:pve-b',
      );
      expect(nodeBCandidate.source, 'node');
      expect(nodeBCandidate.identity, 'pve-b');

      resolver.result = 'node:not-current';
      expect(
        await controller.resolveIncidentNavigationTarget(targetHash),
        isNull,
      );
    },
  );

  test(
    'controller forwards scheduled identities for failed task incidents',
    () async {
      final prefs = await SharedPreferences.getInstance();
      const upid = 'UPID:pve-a:0001:0002:0003:qmstart:100:root@pam:';
      final resolver = _Resolver()..result = 'task:$upid';
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
        nodes: const <Node>[Node(name: 'pve-a', status: 'online')],
        guests: const <Guest>[],
        fetchedAt: DateTime.utc(2026, 11, 14, 12),
      );
      controller.serverTasks = const <RecentServerTask>[
        RecentServerTask(
          upid: upid,
          node: 'pve-a',
          operation: 'qmstart',
          status: 'stopped',
          exitStatus: 'VM is locked',
        ),
      ];
      const targetHash =
          'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';

      expect(
        await controller.resolveIncidentNavigationTarget(targetHash),
        'task:$upid',
      );
      final candidate = resolver.candidates.single;
      expect(candidate.key, 'task:$upid');
      expect(candidate.source, 'task');
      expect(candidate.identity, upid);
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
      fetchedAt: DateTime.now().toUtc(),
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
    expect(resolver.profileId, 'lab');
    expect(resolver.targetHash, targetHash);
    await tester.drag(
      find.byKey(const Key('incident-inbox-list')),
      const Offset(0, -720),
    );
    await tester.pumpAndSettle();
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
