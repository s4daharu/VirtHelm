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
}
