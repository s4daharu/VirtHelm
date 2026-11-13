import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virthelm/core/foreground_notifications.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.s4daharu.virthelm/incident_notifications');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'foreground bridge sends bounded metadata and optional exact target',
    () async {
      MethodCall? observed;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            observed = call;
            return true;
          });

      final shown = await const AndroidForegroundIncidentNotifier()
          .showIncidentSummary(
            critical: true,
            profileId: 'profile-alpha',
            cooldownMinutes: 30,
            incidentKey: 'node:pve-a',
          );

      expect(shown, isTrue);
      expect(observed?.method, 'showIncidentSummary');
      expect(
        Map<String, Object?>.from(observed?.arguments as Map),
        <String, Object?>{
          'critical': true,
          'profileId': 'profile-alpha',
          'cooldownMinutes': 30,
          'incidentKey': 'node:pve-a',
        },
      );
    },
  );

  test(
    'foreground bridge fails closed on invalid deduplication inputs',
    () async {
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls++;
            return true;
          });

      const notifier = AndroidForegroundIncidentNotifier();
      expect(
        await notifier.showIncidentSummary(
          critical: false,
          profileId: '',
          cooldownMinutes: 30,
        ),
        isFalse,
      );
      expect(
        await notifier.showIncidentSummary(
          critical: false,
          profileId: 'profile-alpha',
          cooldownMinutes: -1,
        ),
        isFalse,
      );
      expect(
        await notifier.showIncidentSummary(
          critical: false,
          profileId: 'profile-alpha',
          cooldownMinutes: 1441,
        ),
        isFalse,
      );
      expect(
        await notifier.showIncidentSummary(
          critical: false,
          profileId: 'profile-alpha',
          cooldownMinutes: 30,
          incidentKey: 'bad\nkey',
        ),
        isFalse,
      );
      expect(calls, 0);
    },
  );
}
