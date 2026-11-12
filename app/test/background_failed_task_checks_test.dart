import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virthelm/core/background_checks.dart';
import 'package:virthelm/core/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.s4daharu.virthelm/background_checks');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('scheduled failed-task policy is backward-compatible and opt-in', () {
    final legacy = BackgroundCheckPolicy.fromChannel(<Object?, Object?>{
      'enabled': true,
      'intervalMinutes': 30,
      'quietHoursEnabled': false,
      'quietStartMinute': 1320,
      'quietEndMinute': 420,
      'cooldownMinutes': 30,
    });
    final expanded = BackgroundCheckPolicy.fromChannel(<Object?, Object?>{
      'enabled': true,
      'intervalMinutes': 30,
      'quietHoursEnabled': false,
      'quietStartMinute': 1320,
      'quietEndMinute': 420,
      'cooldownMinutes': 30,
      'failedTaskChecksEnabled': true,
    });

    expect(legacy.failedTaskChecksEnabled, isFalse);
    expect(expanded.failedTaskChecksEnabled, isTrue);
    expect(
      expanded.copyWith(failedTaskChecksEnabled: false).failedTaskChecksEnabled,
      isFalse,
    );
  });

  test('Android scheduler sends failed-task opt-in explicitly', () async {
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
      intervalMinutes: 30,
      cooldownMinutes: 60,
      failedTaskChecksEnabled: true,
    );

    await const AndroidBackgroundCheckScheduler().configure(
      profile,
      credentials,
      policy,
    );

    expect(observed?.method, 'configure');
    final arguments = Map<String, Object?>.from(observed?.arguments as Map);
    expect(arguments['profileId'], 'profile-alpha');
    expect(arguments['failedTaskChecksEnabled'], isTrue);
    expect(arguments['intervalMinutes'], 30);
    expect(arguments['cooldownMinutes'], 60);
  });

  test('scheduled status reports failed-task opt-in without exposing task data', () async {
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
            'failedTaskChecksEnabled': true,
            'lastAttemptMs': 1000,
            'lastSuccessMs': 2000,
            'lastNotificationMs': 3000,
            'lastOutcome': 'task_incident',
          };
        });

    final status = await const AndroidBackgroundCheckScheduler().status(
      'profile-alpha',
    );

    expect(status.enabled, isTrue);
    expect(status.policy.failedTaskChecksEnabled, isTrue);
    expect(status.lastOutcome, 'task_incident');
  });
}
