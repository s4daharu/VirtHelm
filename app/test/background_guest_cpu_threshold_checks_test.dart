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

ForegroundThresholdAlertRule _guestRule({
  String id = 'guest-rule',
  bool enabled = true,
}) => ForegroundThresholdAlertRule(
  id: id,
  metric: ForegroundThresholdMetric.guestCpu,
  node: 'pve-a',
  displayName: 'vm-100',
  thresholdPercent: 90,
  severity: ForegroundAlertSeverity.critical,
  guestKind: 'qemu',
  guestVmid: 100,
  enabled: enabled,
  consecutiveSamples: 2,
  hysteresisPercent: 7,
);

ForegroundThresholdAlertRule _nodeRule() => const ForegroundThresholdAlertRule(
  id: 'node-rule',
  metric: ForegroundThresholdMetric.nodeCpu,
  node: 'pve-a',
  displayName: 'pve-a',
  thresholdPercent: 80,
  severity: ForegroundAlertSeverity.warning,
);

ForegroundThresholdAlertRule _storageRule() =>
    const ForegroundThresholdAlertRule(
      id: 'storage-rule',
      metric: ForegroundThresholdMetric.storageUsage,
      node: 'pve-a',
      displayName: 'local-lvm',
      thresholdPercent: 85,
      severity: ForegroundAlertSeverity.warning,
      storageId: 'local-lvm',
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
    'scheduled guest CPU threshold policy defaults off for legacy status',
    () {
      final legacy = BackgroundCheckPolicy.fromChannel(<Object?, Object?>{
        'enabled': true,
        'intervalMinutes': 30,
        'quietHoursEnabled': false,
        'quietStartMinute': 1320,
        'quietEndMinute': 420,
        'cooldownMinutes': 30,
      });

      expect(legacy.guestCpuThresholdChecksEnabled, isFalse);
      expect(
        legacy
            .copyWith(guestCpuThresholdChecksEnabled: true)
            .guestCpuThresholdChecksEnabled,
        isTrue,
      );
    },
  );

  test('Android configure sends only enabled guest CPU rules', () async {
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
      guestCpuThresholdChecksEnabled: true,
    );

    await const AndroidBackgroundCheckScheduler().configureWithThresholdRules(
      profile,
      credentials,
      policy,
      <ForegroundThresholdAlertRule>[
        _guestRule(),
        _guestRule(id: 'disabled-guest', enabled: false),
        _nodeRule(),
        _storageRule(),
      ],
    );

    expect(observed?.method, 'configure');
    final arguments = Map<String, Object?>.from(observed?.arguments as Map);
    expect(arguments['guestCpuThresholdChecksEnabled'], isTrue);
    expect(arguments['nodeCpuThresholdRules'], isEmpty);
    final rules = List<Object?>.from(
      arguments['guestCpuThresholdRules'] as List<Object?>,
    );
    expect(rules, hasLength(1));
    expect(Map<String, Object?>.from(rules.single as Map), <String, Object?>{
      'id': 'guest-rule',
      'node': 'pve-a',
      'guestKind': 'qemu',
      'vmid': 100,
      'thresholdPercent': 90,
      'consecutiveSamples': 2,
      'hysteresisPercent': 7,
    });
  });

  test('atomic threshold sync sends node, guest and storage rules', () async {
    MethodCall? observed;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          observed = call;
          return true;
        });

    await const AndroidBackgroundCheckScheduler().syncThresholdRules(
      'profile-alpha',
      <ForegroundThresholdAlertRule>[_nodeRule(), _guestRule(), _storageRule()],
    );

    expect(observed?.method, 'syncThresholdRules');
    final arguments = Map<String, Object?>.from(observed?.arguments as Map);
    expect(arguments['nodeCpuThresholdRules'], hasLength(1));
    expect(arguments['guestCpuThresholdRules'], hasLength(1));
    expect(arguments['storageUsageThresholdRules'], hasLength(1));
  });

  test(
    'scheduled status reports guest CPU opt-in without guest identity data',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'status');
            return <String, Object?>{
              'enabled': true,
              'intervalMinutes': 30,
              'quietHoursEnabled': false,
              'quietStartMinute': 1320,
              'quietEndMinute': 420,
              'cooldownMinutes': 30,
              'guestCpuThresholdChecksEnabled': true,
              'lastOutcome': 'guest_threshold_incident',
            };
          });

      final status = await const AndroidBackgroundCheckScheduler().status(
        'profile-alpha',
      );

      expect(status.policy.guestCpuThresholdChecksEnabled, isTrue);
      expect(status.lastOutcome, 'guest_threshold_incident');
    },
  );

  test('controller resynchronizes guest rules after a rule edit', () async {
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
      _guestRule(),
      expectedProfileId: profile.id,
    );

    expect(scheduler.synced, hasLength(1));
    expect(scheduler.synced.single.single.id, 'guest-rule');
    controller.dispose();
  });

  test(
    'failed atomic rule sync disables scheduled monitoring fail-closed',
    () async {
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
          _guestRule(),
          expectedProfileId: profile.id,
        ),
        throwsA(isA<BackgroundCheckException>()),
      );

      expect(scheduler.disables, 1);
      expect(repository.readThresholdAlertRules(profile.id), hasLength(1));
      controller.dispose();
    },
  );
}
