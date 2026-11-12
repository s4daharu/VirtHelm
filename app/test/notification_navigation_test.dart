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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Android bridge consumes the native pending incident target', () async {
    const channel = MethodChannel(
      'com.s4daharu.virthelm/incident_navigation',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'takePendingIncidentIntent');
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    const bridge = AndroidIncidentNotificationNavigation();
    expect(await bridge.takePendingIncidentIntent(), isTrue);
  });

  testWidgets('pending notification request opens Incidents on shell creation', (
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
    controller.requestIncidentCenter();

    await tester.pumpWidget(
      MaterialApp(home: ShellPage(controller: controller)),
    );

    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      3,
    );
  });

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
