import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:virthelm/core/app_controller.dart';
import 'package:virthelm/core/foreground_notifications.dart';
import 'package:virthelm/core/models.dart';
import 'package:virthelm/core/profile_repository.dart';
import 'package:virthelm/ui/shell.dart';

class _Vault implements CredentialVault {
  final Map<String, ApiCredentials> values = <String, ApiCredentials>{};

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

class _MaintenanceNotifier
    implements ForegroundIncidentNotifier, IncidentMaintenanceNotifier {
  final List<DateTime?> maintenanceChanges = <DateTime?>[];

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> setLockScreenPrivacy(
    IncidentNotificationLockScreenPrivacy privacy,
  ) async => true;

  @override
  Future<bool> setMaintenanceUntil({
    required String profileId,
    required DateTime? until,
  }) async {
    maintenanceChanges.add(until);
    return true;
  }

  @override
  Future<bool> showIncidentSummary({
    required bool critical,
    required String profileId,
    required int cooldownMinutes,
    String? incidentKey,
  }) async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.s4daharu.virthelm/incident_notifications');

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('maintenance silence is future-only and bounded to 24 hours', () {
    final now = DateTime.utc(2026, 11, 19, 8);
    final until = now.add(const Duration(hours: 4));

    expect(
      validateIncidentMaintenanceUntil(until, now: now),
      until,
    );
    expect(isIncidentMaintenanceActive(until, now), isTrue);
    expect(
      isIncidentMaintenanceActive(until, until),
      isFalse,
    );
    expect(
      () => validateIncidentMaintenanceUntil(now, now: now),
      throwsFormatException,
    );
    expect(
      () => validateIncidentMaintenanceUntil(
        now.add(const Duration(hours: 24, seconds: 1)),
        now: now,
      ),
      throwsFormatException,
    );
  });

  test('Android bridge sends only profile id and bounded expiry timestamp', () async {
    MethodCall? observed;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          observed = call;
          return true;
        });
    final until = DateTime.now().toUtc().add(const Duration(hours: 1));

    expect(
      await const AndroidForegroundIncidentNotifier().setMaintenanceUntil(
        profileId: 'profile-alpha',
        until: until,
      ),
      isTrue,
    );
    expect(observed?.method, 'setMaintenanceUntil');
    expect(
      Map<String, Object?>.from(observed?.arguments as Map),
      <String, Object?>{
        'profileId': 'profile-alpha',
        'untilMs': until.millisecondsSinceEpoch,
      },
    );
  });

  test('maintenance expiry persists per profile and deletion clears it', () async {
    final prefs = await SharedPreferences.getInstance();
    final repository = ProfileRepository(prefs, _Vault());
    final profile = ConnectionProfile.create(
      name: 'Lab',
      address: 'https://pve.local',
    );
    await repository.save(
      profile,
      const ApiCredentials(
        tokenId: 'operator@pve!mobile',
        secret: 'test-secret',
      ),
    );
    final until = DateTime.utc(2026, 11, 19, 12);

    await repository.saveIncidentNotificationMaintenanceUntil(
      profile.id,
      until,
    );
    expect(
      repository.readIncidentNotificationMaintenanceUntil(profile.id),
      until,
    );

    await repository.delete(profile.id);
    expect(
      repository.readIncidentNotificationMaintenanceUntil(profile.id),
      isNull,
    );
  });

  test('controller applies, persists and clears maintenance silence', () async {
    final prefs = await SharedPreferences.getInstance();
    final repository = ProfileRepository(prefs, _Vault());
    final profile = ConnectionProfile.create(
      name: 'Lab',
      address: 'https://pve.local',
    );
    await repository.save(
      profile,
      const ApiCredentials(
        tokenId: 'operator@pve!mobile',
        secret: 'test-secret',
      ),
    );
    final notifier = _MaintenanceNotifier();
    final controller = AppController(
      repository: repository,
      incidentNotifier: notifier,
    );
    addTearDown(controller.dispose);
    controller.active = profile;
    controller.profiles = <ConnectionProfile>[profile];

    final until = DateTime.now().toUtc().add(const Duration(hours: 4));
    expect(
      await controller.setIncidentNotificationMaintenanceUntil(
        until,
        expectedProfileId: profile.id,
      ),
      isTrue,
    );
    expect(controller.incidentNotificationMaintenanceUntil, until);
    expect(
      repository.readIncidentNotificationMaintenanceUntil(profile.id),
      until,
    );
    expect(notifier.maintenanceChanges, <DateTime?>[until]);

    expect(
      await controller.setIncidentNotificationMaintenanceUntil(
        null,
        expectedProfileId: profile.id,
      ),
      isTrue,
    );
    expect(controller.incidentNotificationMaintenanceUntil, isNull);
    expect(
      repository.readIncidentNotificationMaintenanceUntil(profile.id),
      isNull,
    );
    expect(notifier.maintenanceChanges.last, isNull);

    expect(
      await controller.setIncidentNotificationMaintenanceUntil(
        DateTime.now().toUtc().add(const Duration(hours: 1)),
        expectedProfileId: 'another-profile',
      ),
      isFalse,
    );
  });

  testWidgets('settings expose bounded maintenance silence controls', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final controller = AppController(
      repository: ProfileRepository(prefs, _Vault()),
    );
    addTearDown(controller.dispose);
    const profile = ConnectionProfile(
      id: 'lab',
      name: 'Lab',
      endpoint: 'https://pve.local:8006',
    );
    controller.active = profile;
    controller.profiles = const <ConnectionProfile>[profile];
    controller.incidentNotificationMaintenanceUntil = DateTime.now()
        .toUtc()
        .add(const Duration(hours: 4));

    await tester.pumpWidget(
      MaterialApp(home: ShellPage(controller: controller)),
    );
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('incident-maintenance-1h')),
      260,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.byKey(const Key('incident-maintenance-1h')), findsOneWidget);
    expect(find.byKey(const Key('incident-maintenance-4h')), findsOneWidget);
    expect(find.byKey(const Key('incident-maintenance-12h')), findsOneWidget);
    expect(find.byKey(const Key('incident-maintenance-24h')), findsOneWidget);
    expect(find.byKey(const Key('incident-maintenance-end')), findsOneWidget);
    expect(find.textContaining('Incidents, health, history'), findsOneWidget);
  });
}
