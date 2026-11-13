import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virthelm/core/alert_rules.dart';
import 'package:virthelm/core/background_checks.dart';
import 'package:virthelm/core/models.dart';

const _storage = ForegroundThresholdAlertRule(
  id: 'storage-1',
  metric: ForegroundThresholdMetric.storageUsage,
  node: 'pve-a',
  displayName: 'local-lvm',
  storageId: 'local-lvm',
  thresholdPercent: 85,
  severity: ForegroundAlertSeverity.warning,
  consecutiveSamples: 3,
  hysteresisPercent: 5,
);

const _node = ForegroundThresholdAlertRule(
  id: 'node-1',
  metric: ForegroundThresholdMetric.nodeCpu,
  node: 'pve-a',
  displayName: 'pve-a',
  thresholdPercent: 90,
  severity: ForegroundAlertSeverity.critical,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.s4daharu.virthelm/background_checks');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('legacy scheduled status defaults storage monitoring off', () {
    final policy = BackgroundCheckPolicy.fromChannel(<Object?, Object?>{
      'enabled': true,
      'guestCpuThresholdChecksEnabled': true,
    });
    expect(policy.storageUsageThresholdChecksEnabled, isFalse);
    expect(
      policy
          .copyWith(storageUsageThresholdChecksEnabled: true)
          .storageUsageThresholdChecksEnabled,
      isTrue,
    );
  });

  test('configure sends only enabled storage rules when opted in', () async {
    MethodCall? observed;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          observed = call;
          return true;
        });
    await const AndroidBackgroundCheckScheduler().configureWithThresholdRules(
      const ConnectionProfile(
        id: 'profile-alpha',
        name: 'Lab',
        endpoint: 'https://pve.example:8006',
      ),
      const ApiCredentials(tokenId: 'root@pam!virthelm', secret: 'secret'),
      const BackgroundCheckPolicy(
        enabled: true,
        storageUsageThresholdChecksEnabled: true,
      ),
      <ForegroundThresholdAlertRule>[
        _storage,
        _storage.copyWith(enabled: false),
        _node,
      ],
    );
    final args = Map<String, Object?>.from(observed?.arguments as Map);
    expect(observed?.method, 'configure');
    expect(args['storageUsageThresholdChecksEnabled'], isTrue);
    expect(args['nodeCpuThresholdRules'], isEmpty);
    expect(args['guestCpuThresholdRules'], isEmpty);
    expect(args['storageUsageThresholdRules'], hasLength(1));
    final rule = Map<String, Object?>.from(
      (args['storageUsageThresholdRules'] as List).single as Map,
    );
    expect(rule, <String, Object?>{
      'id': 'storage-1',
      'node': 'pve-a',
      'storageId': 'local-lvm',
      'thresholdPercent': 85,
      'consecutiveSamples': 3,
      'hysteresisPercent': 5,
    });
  });

  test(
    'atomic rule sync carries storage selectors with other categories',
    () async {
      MethodCall? observed;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            observed = call;
            return true;
          });
      await const AndroidBackgroundCheckScheduler().syncThresholdRules(
        'profile-alpha',
        const <ForegroundThresholdAlertRule>[_storage, _node],
      );
      final args = Map<String, Object?>.from(observed?.arguments as Map);
      expect(observed?.method, 'syncThresholdRules');
      expect(args['storageUsageThresholdRules'], hasLength(1));
      expect(args['nodeCpuThresholdRules'], hasLength(1));
      expect(args['guestCpuThresholdRules'], isEmpty);
    },
  );

  test('status exposes storage opt-in and generic outcome only', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => <String, Object?>{
            'enabled': true,
            'storageUsageThresholdChecksEnabled': true,
            'lastOutcome': 'storage_threshold_incident',
          },
        );
    final status = await const AndroidBackgroundCheckScheduler().status(
      'profile-alpha',
    );
    expect(status.policy.storageUsageThresholdChecksEnabled, isTrue);
    expect(status.lastOutcome, 'storage_threshold_incident');
  });
}
