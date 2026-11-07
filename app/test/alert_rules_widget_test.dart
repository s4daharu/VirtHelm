import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:virthelm/core/alert_rules.dart';
import 'package:virthelm/core/app_controller.dart';
import 'package:virthelm/core/models.dart';
import 'package:virthelm/core/profile_repository.dart';
import 'package:virthelm/ui/alert_rules_page.dart';

class _MemoryVault implements CredentialVault {
  final Map<String, ApiCredentials> values = {};

  @override
  Future<void> remove(String id) async {
    values.remove(id);
  }

  @override
  Future<ApiCredentials?> retrieve(String id) async => values[id];

  @override
  Future<void> store(String id, ApiCredentials credentials) async {
    values[id] = credentials;
  }
}

void main() {
  testWidgets('operator can add a foreground threshold rule', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repository = ProfileRepository(prefs, _MemoryVault());
    const profile = ConnectionProfile(
      id: 'lab',
      name: 'Lab',
      endpoint: 'https://pve.local:8006',
    );
    await repository.save(
      profile,
      const ApiCredentials(tokenId: 'user@pve!mobile', secret: 'secret'),
    );
    final controller = AppController(repository: repository);
    addTearDown(controller.dispose);
    controller.active = profile;
    controller.inventory = Inventory.fromResources([
      {'type': 'node', 'node': 'pve1', 'status': 'online', 'cpu': 0.91},
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: ForegroundThresholdAlertRulesPage(
          controller: controller,
          profileId: profile.id,
          generation: controller.connectionGeneration,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('add-threshold-rule')));
    await tester.pumpAndSettle();
    expect(find.text('Add foreground threshold'), findsOneWidget);
    expect(
      find.byKey(const Key('threshold-rule-consecutive-samples')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('threshold-rule-hysteresis-slider')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('confirm-threshold-rule')));
    await tester.pumpAndSettle();

    expect(controller.thresholdAlertRules, hasLength(1));
    expect(
      controller.incidents,
      isEmpty,
      reason: 'Saving rule configuration must not count as a live sample.',
    );
    expect(find.textContaining('80%'), findsOneWidget);
  });

  testWidgets('operator can edit a rule through searchable grouped targets', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repository = ProfileRepository(prefs, _MemoryVault());
    const profile = ConnectionProfile(
      id: 'lab',
      name: 'Lab',
      endpoint: 'https://pve.local:8006',
    );
    await repository.save(
      profile,
      const ApiCredentials(tokenId: 'user@pve!mobile', secret: 'secret'),
    );
    final controller = AppController(repository: repository);
    addTearDown(controller.dispose);
    controller.active = profile;
    controller.inventory = Inventory.fromResources([
      {'type': 'node', 'node': 'pve1', 'status': 'online', 'cpu': 0.91},
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: ForegroundThresholdAlertRulesPage(
          controller: controller,
          profileId: profile.id,
          generation: controller.connectionGeneration,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('add-threshold-rule')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-threshold-rule')));
    await tester.pumpAndSettle();
    expect(controller.thresholdAlertRules, hasLength(1));

    await tester.tap(find.text('pve1'));
    await tester.pumpAndSettle();
    expect(find.text('Edit foreground threshold'), findsOneWidget);

    await tester.tap(find.byKey(const Key('threshold-rule-target')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('threshold-rule-target-search')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('threshold-rule-target-search')),
      'pve1',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('threshold-target-node:pve1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Critical'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-threshold-rule')));
    await tester.pumpAndSettle();

    expect(controller.thresholdAlertRules, hasLength(1));
    expect(
      controller.thresholdAlertRules.single.severity,
      ForegroundAlertSeverity.critical,
    );
    expect(find.textContaining('critical'), findsOneWidget);
  });
}
