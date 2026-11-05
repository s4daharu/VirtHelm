import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:virthelm/core/models.dart';
import 'package:virthelm/core/offline_overview.dart';
import 'package:virthelm/core/profile_repository.dart';

class _Vault implements CredentialVault {
  final Map<String, ApiCredentials> stored = {};
  int writes = 0;

  @override
  Future<void> store(String id, ApiCredentials credentials) async {
    writes++;
    stored[id] = credentials;
  }

  @override
  Future<ApiCredentials?> retrieve(String id) async => stored[id];

  @override
  Future<void> remove(String id) async {
    stored.remove(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const profileA = ConnectionProfile(
    id: 'lab-a',
    name: 'Lab A',
    endpoint: 'https://a.example:8006',
  );
  const profileB = ConnectionProfile(
    id: 'lab-b',
    name: 'Lab B',
    endpoint: 'https://b.example:8006',
  );
  const creds = ApiCredentials(tokenId: 'me@pve!app', secret: 'secret');

  test('summary stores only counts and rejects bad and aged records', () {
    final now = DateTime.utc(2026, 11, 5, 12);
    final inventory = Inventory.fromResources([
      {'type': 'node', 'node': 'private-node', 'status': 'online'},
      {
        'type': 'qemu',
        'vmid': 101,
        'node': 'private-node',
        'name': 'secret-vm-name',
        'status': 'running',
      },
    ], fetchedAt: now.subtract(const Duration(hours: 2)));
    final original = OfflineOverview.fromInventory(inventory);
    final record = original.toJson();
    final serialized = jsonEncode(record);
    expect(serialized, isNot(contains('private-node')));
    expect(serialized, isNot(contains('secret-vm-name')));
    expect(serialized, isNot(contains('101')));
    final decoded = OfflineOverview.fromJson(jsonDecode(serialized), now: now);
    expect(decoded?.totalNodes, 1);
    expect(decoded?.totalGuests, 1);
    expect(decoded?.runningGuests, 1);

    expect(
      OfflineOverview.fromJson({
        ...record,
        'timestampMs': now.add(const Duration(seconds: 1)).millisecondsSinceEpoch,
      }, now: now),
      isNull,
    );
    expect(
      OfflineOverview.fromJson({
        ...record,
        'timestampMs': now.subtract(const Duration(days: 8)).millisecondsSinceEpoch,
      }, now: now),
      isNull,
    );
    expect(
      OfflineOverview.fromJson({...record, 'runningGuests': 2}, now: now),
      isNull,
    );
    expect(
      OfflineOverview.fromJson({...record, 'v': 2}, now: now),
      isNull,
    );
    expect(
      OfflineOverview.fromJson({...record, 'hostname': 'private'}, now: now),
      isNull,
    );
    expect(
      OfflineOverview.fromJson({...record, 'totalGuests': '1'}, now: now),
      isNull,
    );
  });

  test('opt-in is profile-isolated and removal purges preferences', () async {
    final prefs = await SharedPreferences.getInstance();
    final vault = _Vault();
    final repo = ProfileRepository(prefs, vault);
    await repo.save(profileA, creds);
    await repo.save(profileB, creds);
    final example = OfflineOverview(
      fetchedAt: DateTime.now(),
      totalNodes: 1,
      onlineNodes: 1,
      totalGuests: 2,
      runningGuests: 1,
      stoppedGuests: 1,
    );
    await repo.saveOfflineOverview(profileA.id, example);
    expect(repo.offlineOverviewEnabled(profileA.id), isFalse);
    expect(repo.readOfflineOverview(profileA.id), isNull);

    await repo.setOfflineOverviewEnabled(profileA.id, true);
    await repo.saveOfflineOverview(profileA.id, example);
    expect(repo.readOfflineOverview(profileA.id)?.totalGuests, 2);
    expect(repo.readOfflineOverview(profileB.id), isNull);
    expect(repo.offlineOverviewEnabled(profileB.id), isFalse);
    expect(vault.writes, 2);

    await prefs.setBool('offline_counts_v1:lab-b', true);
    await repo.setOfflineOverviewEnabled(profileB.id, true);
    expect(repo.readOfflineOverview(profileB.id), isNull);
    await repo.delete(profileA.id);
    expect(repo.readOfflineOverview(profileA.id), isNull);
    expect(repo.offlineOverviewEnabled(profileA.id), isFalse);
    expect(prefs.get('offline_counts_v1:lab-a'), isNull);
    await expectLater(
      repo.setOfflineOverviewEnabled(profileA.id, true),
      throwsA(isA<StateError>()),
    );
  });

  test('opt-out and credential edit purge counts without vault rewrites', () async {
    final prefs = await SharedPreferences.getInstance();
    final vault = _Vault();
    final repo = ProfileRepository(prefs, vault);
    await repo.save(profileA, creds);
    final example = OfflineOverview(
      fetchedAt: DateTime.now(),
      totalNodes: 1,
      onlineNodes: 1,
      totalGuests: 1,
      runningGuests: 1,
      stoppedGuests: 0,
    );
    await repo.setOfflineOverviewEnabled(profileA.id, true);
    await repo.saveOfflineOverview(profileA.id, example);
    expect(vault.writes, 1);
    await repo.setOfflineOverviewEnabled(profileA.id, false);
    expect(prefs.get('offline_counts_v1:lab-a'), isNull);
    expect(repo.offlineOverviewEnabled(profileA.id), isFalse);
    expect(vault.writes, 1);

    await repo.setOfflineOverviewEnabled(profileA.id, true);
    await repo.saveOfflineOverview(profileA.id, example);
    await repo.update(
      const ConnectionProfile(
        id: 'lab-a',
        name: 'Updated',
        endpoint: 'https://new.example:8006',
      ),
      creds,
    );
    expect(repo.readOfflineOverview(profileA.id), isNull);
    expect(repo.offlineOverviewEnabled(profileA.id), isTrue);
    expect(vault.writes, 2);
  });
}
