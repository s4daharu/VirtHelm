import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:virthelm/core/alert_rules.dart';
import 'package:virthelm/core/app_controller.dart';
import 'package:virthelm/core/background_checks.dart';
import 'package:virthelm/core/models.dart';
import 'package:virthelm/core/profile_repository.dart';

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

class _Scheduler
    implements
        BackgroundCheckScheduler,
        ThresholdAwareBackgroundCheckScheduler {
  final List<List<ForegroundThresholdAlertRule>> synced = [];
  int disables = 0;
  bool failSync = false;

  @override
  Future<BackgroundCheckStatus> status(String profileId) async =>
      const BackgroundCheckStatus();

  @override
  Future<void> configure(
    ConnectionProfile profile,
    ApiCredentials credentials,
    BackgroundCheckPolicy policy,
  ) async {}

  @override
  Future<void> configureWithThresholdRules(
    ConnectionProfile profile,
    ApiCredentials credentials,
    BackgroundCheckPolicy policy,
    Iterable<ForegroundThresholdAlertRule> rules,
  ) async {}

  @override
  Future<void> syncThresholdRules(
    String profileId,
    Iterable<ForegroundThresholdAlertRule> rules,
  ) async {
    synced.add(List<ForegroundThresholdAlertRule>.from(rules));
    if (failSync) {
      throw const BackgroundCheckException('sync failed');
    }
  }

  @override
  Future<void> disable(String profileId, {bool clearPolicy = false}) async {
    disables++;
  }
}

ForegroundThresholdAlertRule _nodeRule({
  String id = 'node-rule',
  bool enabled = true,
}) => ForegroundThresholdAlertRule(
  id: id,
  metric: ForegroundThresholdMetric.nodeCpu,
  node: 'pve-a',
  displayName: 'pve-a',
  thresholdPercent: 80,
  severity: ForegroundAlertSeverity.warning,
  enabled: enabled,
  consecutiveSamples: 3,
  hysteresisPercent: 5,
);

ForegroundThresholdAlertRule _guestRule() => const ForegroundThresholdAlertRule(
  id: 'guest-rule',
  metric: ForegroundThresholdMetric.guestCpu,
  node: 'pve-a',
  displayName: 'vm-100',
  thresholdPercent: 90,
  severity: ForegroundAlertSeverity.critical,
  guestKind: 'qemu',
  guestVmid: 100,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.s4daharu.virthelm/background_checks');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'scheduled node CPU threshold policy defaults off for legacy status',
    () {
      final legacy = BackgroundCheckPolicy.fromChannel(<Object?, Object?>{
        'enabled': true,
        'intervalMinutes': 30,
        'quietHoursEnabled': false,
        'quietStartMinute': 1320,
        'quietEndMinute': 420,
        'cooldownMinutes': 30,
      });

      expect(legacy.nodeCpuThresholdChecksEnabled, isFalse);
      expect(
        legacy
            .copyWith(nodeCpuThresholdChecksEnabled: true)
            .nodeCpuThresholdChecksEnabled,
        isTrue,
      );
    },
  );

  test('Android configure sends only enabled node CPU rules', () async {
    MethodCall? observed;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          observed = call;
          return true;
        });

    const profile = ConnectionProfile(
      id: 'profile-alpha',
      name: 'Lab',
      endpoint: 'https://pve.example:8006',
    );
    const credentials = ApiCredentials(
      tokenId: 'root@pam!virthelm',
      secret: 'secret',
    );
    const policy = BackgroundCheckPolicy(
      enabled: true,
      nodeCpuThresholdChecksEnabled: true,
    );

    await const AndroidBackgroundCheckScheduler().configureWithThresholdRules(
      profile,
      credentials,
      policy,
      <ForegroundThresholdAlertRule>[
        _nodeRule(),
        _nodeRule(id: 'disabled-node', enabled: false),
        _guestRule(),
      ],
    );

    expect(observed?.method, 'configure');
    final arguments = Map<String, Object?>.from(observed?.arguments as Map);
    expect(arguments['nodeCpuThresholdChecksEnabled'], isTrue);
    expect(arguments['guestCpuThresholdChecksEnabled'], isFalse);
    expect(arguments['guestCpuThresholdRules'], isEmpty);
    final rules = List<Object?>.from(
      arguments['nodeCpuThresholdRules'] as List<Object?>,
    );
    expect(rules, hasLength(1));
    expect(Map<String, Object?>.from(rules.single as Map), <String, Object?>{
      'id': 'node-rule',
      'node': 'pve-a',
      'thresholdPercent': 80,
      'consecutiveSamples': 3,
      'hysteresisPercent': 5,
    });
  });

  test(
    'Android rule sync serializes node and guest threshold targets',
    () async {
      MethodCall? observed;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            observed = call;
            return true;
          });

      await const AndroidBackgroundCheckScheduler().syncThresholdRules(
        'profile-alpha',
        <ForegroundThresholdAlertRule>[_nodeRule(), _guestRule()],
      );

      expect(observed?.method, 'syncThresholdRules');
      final arguments = Map<String, Object?>.from(observed?.arguments as Map);
      final rules = List<Object?>.from(
        arguments['nodeCpuThresholdRules'] as List<Object?>,
      );
      final guestRules = List<Object?>.from(
        arguments['guestCpuThresholdRules'] as List<Object?>,
      );
      expect(rules, hasLength(1));
      expect(guestRules, hasLength(1));
      expect(Map<String, Object?>.from(rules.single as Map)['id'], 'node-rule');
      expect(
        Map<String, Object?>.from(guestRules.single as Map)['id'],
        'guest-rule',
      );
    },
  );

  test('controller resynchronizes worker rules after a rule edit', () async {
    final prefs = await SharedPreferences.getInstance();
    final vault = _Vault();
    final repository = ProfileRepository(prefs, vault);
    const profile = ConnectionProfile(
      id: 'profile-alpha',
      name: 'Lab',
      endpoint: 'https://pve.example:8006',
    );
    const credentials = ApiCredentials(
      tokenId: 'root@pam!virthelm',
      secret: 'secret',
    );
    await repository.save(profile, credentials);

    final scheduler = _Scheduler();
    final controller = AppController(
      repository: repository,
      backgroundCheckScheduler: scheduler,
    );
    controller.active = profile;

    await controller.saveThresholdAlertRule(
      _nodeRule(),
      expectedProfileId: profile.id,
    );

    expect(scheduler.synced, hasLength(1));
    expect(scheduler.synced.single.single.id, 'node-rule');
    controller.dispose();
  });

  test('failed rule sync disables scheduled monitoring fail-closed', () async {
    final prefs = await SharedPreferences.getInstance();
    final vault = _Vault();
    final repository = ProfileRepository(prefs, vault);
    const profile = ConnectionProfile(
      id: 'profile-alpha',
      name: 'Lab',
      endpoint: 'https://pve.example:8006',
    );
    const credentials = ApiCredentials(
      tokenId: 'root@pam!virthelm',
      secret: 'secret',
    );
    await repository.save(profile, credentials);

    final scheduler = _Scheduler()..failSync = true;
    final controller = AppController(
      repository: repository,
      backgroundCheckScheduler: scheduler,
    );
    controller.active = profile;

    await expectLater(
      controller.saveThresholdAlertRule(
        _nodeRule(),
        expectedProfileId: profile.id,
      ),
      throwsA(isA<BackgroundCheckException>()),
    );

    expect(scheduler.disables, 1);
    expect(repository.readThresholdAlertRules(profile.id), hasLength(1));
    controller.dispose();
  });
}
