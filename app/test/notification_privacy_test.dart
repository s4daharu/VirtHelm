import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:virthelm/core/app_controller.dart';
import 'package:virthelm/core/foreground_notifications.dart';
import 'package:virthelm/core/models.dart';
import 'package:virthelm/core/profile_repository.dart';

class _Vault implements CredentialVault {
  @override
  Future<void> store(String id, ApiCredentials credentials) async {}

  @override
  Future<ApiCredentials?> retrieve(String id) async => null;

  @override
  Future<void> remove(String id) async {}
}

class _FailingPrivacyRepository extends ProfileRepository {
  _FailingPrivacyRepository(SharedPreferences prefs) : super(prefs, _Vault());

  @override
  Future<void> setNotificationLockScreenPrivacy(
    IncidentNotificationLockScreenPrivacy value,
  ) async {
    throw StateError('privacy persistence failed');
  }
}

class _PausedPrivacyNotifier extends _Notifier {
  final Completer<void> secondCallStarted = Completer<void>();
  final Completer<void> secondCallGate = Completer<void>();
  int calls = 0;

  @override
  Future<bool> setLockScreenPrivacy(
    IncidentNotificationLockScreenPrivacy privacy,
  ) async {
    privacyChanges.add(privacy);
    calls++;
    if (calls == 2) {
      secondCallStarted.complete();
      await secondCallGate.future;
    }
    return true;
  }
}

class _Notifier implements ForegroundIncidentNotifier {
  final List<IncidentNotificationLockScreenPrivacy> privacyChanges = [];
  bool applyPrivacy = true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> setLockScreenPrivacy(
    IncidentNotificationLockScreenPrivacy privacy,
  ) async {
    privacyChanges.add(privacy);
    return applyPrivacy;
  }

  @override
  Future<bool> showIncidentSummary({
    required bool critical,
    required String profileId,
    required int cooldownMinutes,
  }) async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('lock-screen privacy storage defaults fail closed', () {
    expect(
      incidentNotificationLockScreenPrivacyFromStorage(null),
      IncidentNotificationLockScreenPrivacy.hidden,
    );
    expect(
      incidentNotificationLockScreenPrivacyFromStorage('unexpected'),
      IncidentNotificationLockScreenPrivacy.hidden,
    );
    expect(
      incidentNotificationLockScreenPrivacyFromStorage('generic'),
      IncidentNotificationLockScreenPrivacy.generic,
    );
  });

  test('controller initializes and synchronizes persisted privacy', () async {
    final prefs = await SharedPreferences.getInstance();
    final repository = ProfileRepository(prefs, _Vault());
    await repository.setNotificationLockScreenPrivacy(
      IncidentNotificationLockScreenPrivacy.generic,
    );
    final notifier = _Notifier();
    final controller = AppController(
      repository: repository,
      incidentNotifier: notifier,
    );

    await controller.initialize();

    expect(
      controller.notificationLockScreenPrivacy,
      IncidentNotificationLockScreenPrivacy.generic,
    );
    expect(notifier.privacyChanges, [
      IncidentNotificationLockScreenPrivacy.generic,
    ]);
    controller.dispose();
  });

  test(
    'privacy change persists only after native application succeeds',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final repository = ProfileRepository(prefs, _Vault());
      final notifier = _Notifier();
      final controller = AppController(
        repository: repository,
        incidentNotifier: notifier,
      );
      await controller.initialize();

      notifier.applyPrivacy = false;
      expect(
        await controller.setNotificationLockScreenPrivacy(
          IncidentNotificationLockScreenPrivacy.generic,
        ),
        isFalse,
      );
      expect(
        controller.notificationLockScreenPrivacy,
        IncidentNotificationLockScreenPrivacy.hidden,
      );
      expect(
        repository.notificationLockScreenPrivacy,
        IncidentNotificationLockScreenPrivacy.hidden,
      );

      notifier.applyPrivacy = true;
      expect(
        await controller.setNotificationLockScreenPrivacy(
          IncidentNotificationLockScreenPrivacy.generic,
        ),
        isTrue,
      );
      expect(
        controller.notificationLockScreenPrivacy,
        IncidentNotificationLockScreenPrivacy.generic,
      );
      expect(
        repository.notificationLockScreenPrivacy,
        IncidentNotificationLockScreenPrivacy.generic,
      );
      controller.dispose();
    },
  );

  test(
    'controller shutdown rolls an in-flight native privacy change back',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final repository = ProfileRepository(prefs, _Vault());
      final notifier = _PausedPrivacyNotifier();
      final controller = AppController(
        repository: repository,
        incidentNotifier: notifier,
      );
      await controller.initialize();

      final change = controller.setNotificationLockScreenPrivacy(
        IncidentNotificationLockScreenPrivacy.generic,
      );
      await notifier.secondCallStarted.future;
      controller.dispose();
      notifier.secondCallGate.complete();

      expect(await change, isFalse);
      expect(
        repository.notificationLockScreenPrivacy,
        IncidentNotificationLockScreenPrivacy.hidden,
      );
      expect(notifier.privacyChanges, [
        IncidentNotificationLockScreenPrivacy.hidden,
        IncidentNotificationLockScreenPrivacy.generic,
        IncidentNotificationLockScreenPrivacy.hidden,
      ]);
    },
  );

  test('persistence failure rolls native privacy back to prior mode', () async {
    final prefs = await SharedPreferences.getInstance();
    final repository = _FailingPrivacyRepository(prefs);
    final notifier = _Notifier();
    final controller = AppController(
      repository: repository,
      incidentNotifier: notifier,
    );
    await controller.initialize();

    await expectLater(
      controller.setNotificationLockScreenPrivacy(
        IncidentNotificationLockScreenPrivacy.generic,
      ),
      throwsStateError,
    );

    expect(
      controller.notificationLockScreenPrivacy,
      IncidentNotificationLockScreenPrivacy.hidden,
    );
    expect(notifier.privacyChanges, [
      IncidentNotificationLockScreenPrivacy.hidden,
      IncidentNotificationLockScreenPrivacy.generic,
      IncidentNotificationLockScreenPrivacy.hidden,
    ]);
    controller.dispose();
  });
}
