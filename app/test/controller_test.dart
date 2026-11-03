import 'dart:async';

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

class _PausedVault extends _Vault {
  final removeGate = Completer<void>();

  @override
  Future<void> remove(String id) async {
    await removeGate.future;
    await super.remove(id);
  }
}

class _Gateway implements PveGateway {
  int submissions = 0;
  String status = 'running';
  bool connected = true;
  Completer<String>? preflight;
  PveFailure? submissionError;
  ServerTaskStatus taskResult = const ServerTaskStatus(status: 'running');
  @override
  Future<String> version() async => '9.2';
  @override
  Future<Inventory> inventory() async => Inventory.fromResources([
    {'type': 'node', 'node': 'pve1', 'status': 'online'},
    {'type': 'qemu', 'vmid': 101, 'node': 'pve1', 'name': 'Web', 'status': status},
  ]);
  @override
  Future<String> guestStatus(Guest guest) =>
      preflight?.future ?? Future.value(status);
  @override
  Future<String> submit(Guest guest, GuestAction action) async {
    submissions++;
    if (submissionError != null) throw submissionError!;
    return 'UPID:pve1:1234:123:abc:qmshutdown:101:operator@pve:';
  }
  @override
  Future<ServerTaskStatus> taskStatus(TrackedTask task) async => taskResult;
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
    await ctl.runAction(guest, GuestAction.shutdown, profileId: ctl.active!.id);
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
    await expectLater(ctl.runAction(guest, GuestAction.shutdown, profileId: ctl.active!.id), throwsA(isA<PveFailure>()));
    expect(gateway.submissions, 0);
  });

  test('double submission is blocked during preflight and while task runs', () async {
    final prefs = await SharedPreferences.getInstance();
    final gateways = <_Gateway>[];
    final ctl = AppController(
      repository: ProfileRepository(prefs, _Vault()),
      gatewayFactory: (p, c) {
        final gateway = _Gateway();
        gateways.add(gateway);
        return gateway;
      },
    );
    addTearDown(ctl.dispose);
    await ctl.initialize();
    await ctl.connect(
      name: 'Lab', address: 'https://pve.local',
      tokenId: 'me@pve!app', secret: 's3cr3t',
    );
    final gateway = gateways.last;
    final guest = ctl.inventory!.guests.single;
    final profileId = ctl.active!.id;
    gateway.preflight = Completer<String>();

    final first = ctl.runAction(guest, GuestAction.shutdown, profileId: profileId);
    expect(ctl.isGuestActionBlocked(guest), isTrue);
    await expectLater(
      ctl.runAction(guest, GuestAction.shutdown, profileId: profileId),
      throwsA(isA<PveFailure>()),
    );
    expect(gateway.submissions, 0);
    gateway.preflight!.complete('running');
    await first;
    expect(gateway.submissions, 1);
    expect(ctl.isGuestActionBlocked(guest), isTrue);
    await expectLater(
      ctl.runAction(guest, GuestAction.reboot, profileId: profileId),
      throwsA(isA<PveFailure>()),
    );
    expect(gateway.submissions, 1);
  });

  test('ambiguous POST failure blocks further writes to that guest', () async {
    final prefs = await SharedPreferences.getInstance();
    late _Gateway gateway;
    final ctl = AppController(
      repository: ProfileRepository(prefs, _Vault()),
      gatewayFactory: (p, c) => gateway = _Gateway(),
    );
    addTearDown(ctl.dispose);
    await ctl.initialize();
    await ctl.connect(
      name: 'Lab', address: 'https://pve.local',
      tokenId: 'me@pve!app', secret: 's3cr3t',
    );
    final guest = ctl.inventory!.guests.single;
    final profileId = ctl.active!.id;
    gateway.submissionError = const PveFailure(
      'Timed out after submit; check task history.',
      mayHaveExecuted: true,
    );
    await expectLater(
      ctl.runAction(guest, GuestAction.shutdown, profileId: profileId),
      throwsA(isA<PveFailure>()),
    );
    expect(ctl.isGuestActionBlocked(guest), isTrue);
    gateway.submissionError = null;
    await expectLater(
      ctl.runAction(guest, GuestAction.stop, profileId: profileId),
      throwsA(isA<PveFailure>()),
    );
    expect(gateway.submissions, 1);
  });

  test('replaced inventory snapshot cannot authorize a stale guest', () async {
    final prefs = await SharedPreferences.getInstance();
    late _Gateway gateway;
    final ctl = AppController(
      repository: ProfileRepository(prefs, _Vault()),
      gatewayFactory: (p, c) => gateway = _Gateway(),
    );
    addTearDown(ctl.dispose);
    await ctl.initialize();
    await ctl.connect(
      name: 'Lab', address: 'https://pve.local',
      tokenId: 'me@pve!app', secret: 's3cr3t',
    );
    final oldGuest = ctl.inventory!.guests.single;
    await ctl.refresh();
    await expectLater(
      ctl.runAction(
        oldGuest, GuestAction.shutdown, profileId: ctl.active!.id,
      ),
      throwsA(isA<PveFailure>()),
    );
    expect(gateway.submissions, 0);
  });

  test('profile activation during preflight cancels the old action', () async {
    final prefs = await SharedPreferences.getInstance();
    final gateways = <_Gateway>[];
    final ctl = AppController(
      repository: ProfileRepository(prefs, _Vault()),
      gatewayFactory: (p, c) {
        final gateway = _Gateway();
        gateways.add(gateway);
        return gateway;
      },
    );
    addTearDown(ctl.dispose);
    await ctl.initialize();
    await ctl.connect(
      name: 'Lab', address: 'https://pve.local',
      tokenId: 'me@pve!app', secret: 's3cr3t',
    );
    final previous = gateways.last;
    final guest = ctl.inventory!.guests.single;
    previous.preflight = Completer<String>();
    final action = ctl.runAction(
      guest, GuestAction.shutdown, profileId: ctl.active!.id,
    );
    await ctl.activate(ctl.active!);
    previous.preflight!.complete('running');
    await expectLater(action, throwsA(isA<PveFailure>()));
    expect(previous.submissions, 0);
    expect(gateways.last.submissions, 0);
    expect(ctl.tasks, isEmpty);
  });

  test('terminal UPID result releases a guest for a new verified action', () async {
    final prefs = await SharedPreferences.getInstance();
    late _Gateway gateway;
    final ctl = AppController(
      repository: ProfileRepository(prefs, _Vault()),
      gatewayFactory: (p, c) => gateway = _Gateway(),
    );
    addTearDown(ctl.dispose);
    await ctl.initialize();
    await ctl.connect(
      name: 'Lab', address: 'https://pve.local',
      tokenId: 'me@pve!app', secret: 's3cr3t',
    );
    gateway.taskResult = const ServerTaskStatus(
      status: 'stopped', exitStatus: 'OK',
    );
    final guest = ctl.inventory!.guests.single;
    await ctl.runAction(
      guest, GuestAction.shutdown, profileId: ctl.active!.id,
    );
    // Polling is asynchronous and reconciliation replaces the old snapshot.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(ctl.tasks.single.outcome, OperationOutcome.succeeded);
    expect(ctl.isGuestActionBlocked(guest), isFalse);
    expect(ctl.inventory!.guests.single, isNot(same(guest)));
  });

  test('deleting an active profile invalidates preflight before vault I/O completes', () async {
    final prefs = await SharedPreferences.getInstance();
    final vault = _PausedVault();
    final gateways = <_Gateway>[];
    final ctl = AppController(
      repository: ProfileRepository(prefs, vault),
      gatewayFactory: (p, c) {
        final gateway = _Gateway();
        gateways.add(gateway);
        return gateway;
      },
    );
    addTearDown(ctl.dispose);
    await ctl.initialize();
    await ctl.connect(
      name: 'Lab', address: 'https://pve.local',
      tokenId: 'me@pve!app', secret: 's3cr3t',
    );
    final gateway = gateways.last;
    final guest = ctl.inventory!.guests.single;
    final profileId = ctl.active!.id;
    gateway.preflight = Completer<String>();
    final action = ctl.runAction(
      guest, GuestAction.shutdown, profileId: profileId,
    );

    final deleting = ctl.deleteProfile(profileId);
    expect(ctl.active, isNull);
    gateway.preflight!.complete('running');
    await expectLater(action, throwsA(isA<PveFailure>()));
    expect(gateway.submissions, 0);

    vault.removeGate.complete();
    await deleting;
    expect(ctl.profiles, isEmpty);
  });


}

