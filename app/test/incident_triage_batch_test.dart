import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:virthelm/core/app_controller.dart';
import 'package:virthelm/core/models.dart';
import 'package:virthelm/core/profile_repository.dart';

class _EmptyVault implements CredentialVault {
  @override
  Future<void> store(String id, ApiCredentials credentials) async {}

  @override
  Future<ApiCredentials?> retrieve(String id) async => null;

  @override
  Future<void> remove(String id) async {}
}

void main() {
  test('batch review checks generation, profile and active keys', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = AppController(
      repository: ProfileRepository(prefs, _EmptyVault()),
    );
    addTearDown(controller.dispose);
    controller.active = const ConnectionProfile(
      id: 'one',
      name: 'One',
      endpoint: 'https://one.invalid',
    );
    controller.inventory = Inventory.fromResources([
      {'type': 'node', 'node': 'pve1', 'status': 'offline'},
      {'type': 'node', 'node': 'pve2', 'status': 'offline'},
    ]);
    final generation = controller.connectionGeneration;
    expect(
      controller.acknowledgeIncidents(
        ['node:pve1', 'node:pve1', 'missing'],
        expectedProfileId: 'one',
        expectedGeneration: generation,
      ),
      1,
    );
    expect(controller.incidents, hasLength(2));
    expect(
      controller.currentIncidentTriage.where((record) => record.isAcknowledged),
      hasLength(1),
    );
    expect(
      controller.acknowledgeIncidents(
        ['node:pve2'],
        expectedProfileId: 'one',
        expectedGeneration: generation + 1,
      ),
      0,
    );
    controller.active = const ConnectionProfile(
      id: 'two',
      name: 'Two',
      endpoint: 'https://two.invalid',
    );
    expect(
      controller.acknowledgeIncidents(
        ['node:pve2'],
        expectedProfileId: 'one',
        expectedGeneration: generation,
      ),
      0,
    );
    expect(
      controller.currentIncidentTriage.where((record) => record.isAcknowledged),
      hasLength(1),
    );
  });
}
