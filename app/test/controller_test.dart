import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:virthelm/core/app_controller.dart';
import 'package:virthelm/core/models.dart';
import 'package:virthelm/core/profile_repository.dart';
import 'package:virthelm/core/pve_api.dart';

class _Vault implements CredentialVault {
  final Map<String, ApiCredentials> values = {};
  @override
  Future<void> store(String id, ApiCredentials creds) async { values[id] = creds; }
  @override
  Future<ApiCredentials?> retrieve(String id) async => values[id];
  @override
  Future<void> remove(String id) async { values.remove(id); }
}

class _Gateway implements PveGateway {
  int submissions = 0;
  String status = 'running';
  bool connected = true;
  @override
  Future<String> version() async => '9.2';
  @override
  Future<Inventory> inventory() async => Inventory.fromResources([
    {'type': 'node', 'node': 'pve1', 'status': 'online'},
    {'type': 'qemu', 'vmid': 101, 'node': 'pve1', 'name': 'Web', 'status': status},
  ]);
  @override
  Future<String> guestStatus(Guest guest) async => status;
  @override
  Future<String> submit(Guest guest, GuestAction action) async {
    submissions++;
    return 'UPID:pve1:1234:123:abc:qmshutdown:101:operator@pve:';
  }
  @override
  Future<ServerTaskStatus> taskStatus(TrackedTask task) async =>
      const ServerTaskStatus(status: 'running');
  @override
  void close() { connected = false; }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('profile secrets are outside unencrypted preference records', () async {
    final prefs = await SharedPreferences.getInstance();
    final vault = _Vault();
    final repo = ProfileRepository(prefs, vault);
    final profile = ConnectionProfile.create(name: 'Lab', address: 'https://pve.local');
    const creds = ApiCredentials(tokenId: 'me@pve!app', secret: 's3cr3t');
    await repo.save(profile, creds);
    expect(prefs.getString('profile_metadata_v1'), isNot(contains('s3cr3t')));
    expect(prefs.getString('profile_metadata_v1'), isNot(contains('me@pve!app')));
    expect((await vault.retrieve(profile.id))?.secret, 's3cr3t');
    await repo.delete(profile.id);
    expect(await vault.retrieve(profile.id), isNull);
  });

  test('submits a guarded write only once and tracks a UPID', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = ProfileRepository(prefs, _Vault());
    final gateways = <_Gateway>[];
    final ctl = AppController(repository: repo, gatewayFactory: (p, c) {
      final gateway = _Gateway();
      gateways.add(gateway);
      return gateway;
    });
    addTearDown(ctl.dispose);
    await ctl.initialize();
    await ctl.connect(name: 'Lab', address: 'https://pve.local:8006',
        tokenId: 'me@pve!app', secret: 's3cr3t');
    final guest = ctl.inventory!.guests.single;
    await ctl.runAction(guest, GuestAction.shutdown);
    expect(gateways.last.submissions, 1);
    expect(ctl.tasks.length, 1);
    expect(ctl.tasks.single.outcome, OperationOutcome.running);
  });

  test('stale or changed guest state blocks dangerous mutation', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = ProfileRepository(prefs, _Vault());
    late _Gateway gateway;
    final ctl = AppController(repository: repo, gatewayFactory: (p, c) {
      gateway = _Gateway();
      return gateway;
    });
    addTearDown(ctl.dispose);
    await ctl.initialize();
    await ctl.connect(name: 'Lab', address: 'https://pve.local',
        tokenId: 'me@pve!app', secret: 's3cr3t');
    gateway.status = 'stopped';
    final guest = ctl.inventory!.guests.single;
    await expectLater(ctl.runAction(guest, GuestAction.shutdown), throwsA(isA<PveFailure>()));
    expect(gateway.submissions, 0);
  });
}
