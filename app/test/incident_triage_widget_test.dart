import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:virthelm/core/app_controller.dart';
import 'package:virthelm/core/models.dart';
import 'package:virthelm/core/profile_repository.dart';
import 'package:virthelm/ui/incident_center_tab.dart';

class _EmptyVault implements CredentialVault {
  @override
  Future<void> store(String id, ApiCredentials credentials) async {}

  @override
  Future<ApiCredentials?> retrieve(String id) async => null;

  @override
  Future<void> remove(String id) async {}
}

void main() {
  testWidgets('mobile inbox acknowledges without hiding the incident itself', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = AppController(
      repository: ProfileRepository(prefs, _EmptyVault()),
    );
    addTearDown(controller.dispose);
    controller.active = const ConnectionProfile(
      id: 'a',
      name: 'Test',
      endpoint: 'https://example.invalid',
    );
    controller.inventory = Inventory.fromResources([
      {'type': 'node', 'node': 'pve1', 'status': 'offline'},
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedBuilder(
          animation: controller,
          builder: (context, _) =>
              Scaffold(body: IncidentCenterTab(controller: controller)),
        ),
      ),
    );
    expect(find.text('Node pve1 is offline'), findsOneWidget);
    expect(find.textContaining('Needs review (1)'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('incident-triage-action-node:pve1')),
    );
    await tester.tap(find.byKey(const Key('incident-triage-action-node:pve1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Needs review (0)'), findsOneWidget);
    expect(controller.incidents, hasLength(1));

    await tester.tap(find.textContaining('Acknowledged (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Node pve1 is offline'), findsOneWidget);
    expect(find.text('Mark as unreviewed'), findsOneWidget);
    await tester.tap(find.text('Mark as unreviewed'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Acknowledged (0)'), findsOneWidget);
  });
  testWidgets('search and source filters bulk review only shown signals', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = AppController(
      repository: ProfileRepository(prefs, _EmptyVault()),
    );
    addTearDown(controller.dispose);
    controller.active = const ConnectionProfile(
      id: 'a',
      name: 'Test',
      endpoint: 'https://example.invalid',
    );
    controller.inventory = Inventory.fromResources([
      {'type': 'node', 'node': 'pve1', 'status': 'offline'},
      {'type': 'node', 'node': 'pve2', 'status': 'offline'},
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: IncidentCenterTab(controller: controller)),
      ),
    );
    expect(controller.incidents, hasLength(2));
    await tester.enterText(find.byKey(const Key('incident-search')), 'pve1');
    await tester.pumpAndSettle();
    expect(find.text('Node pve1 is offline'), findsOneWidget);
    expect(find.text('Node pve2 is offline'), findsNothing);
    expect(find.text('Acknowledge shown (1)'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('incident-bulk-acknowledge')));
    await tester.tap(find.byKey(const Key('incident-bulk-acknowledge')));
    await tester.pumpAndSettle();
    expect(find.text('Acknowledge 1 shown signals?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('incident-bulk-confirm')));
    await tester.pumpAndSettle();
    expect(controller.incidents, hasLength(2));
    expect(
      controller.currentIncidentTriage.where((record) => record.isAcknowledged),
      hasLength(1),
    );
    await tester.ensureVisible(find.byKey(const Key('incident-reset-filters')));
    await tester.tap(find.byKey(const Key('incident-reset-filters')));
    await tester.pumpAndSettle();
    expect(find.text('Node pve2 is offline'), findsOneWidget);
    await tester.ensureVisible(find.text('Tasks'));
    await tester.tap(find.text('Tasks').last);
    await tester.pumpAndSettle();
    expect(find.text('No matching signals'), findsOneWidget);
  });

  testWidgets('320dp mobile inbox supports 200% text and readable severity', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 1280);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = AppController(
      repository: ProfileRepository(prefs, _EmptyVault()),
    );
    addTearDown(controller.dispose);
    controller.active = const ConnectionProfile(
      id: 'a',
      name: 'Test',
      endpoint: 'https://example.invalid',
    );
    controller.inventory = Inventory.fromResources([
      {'type': 'node', 'node': 'pve1', 'status': 'offline'},
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(body: IncidentCenterTab(controller: controller)),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Node pve1 is offline'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('CRITICAL'), findsOneWidget);
  });

}
