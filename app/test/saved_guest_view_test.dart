import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:virthelm/core/guest_list_filter.dart';
import 'package:virthelm/core/guest_saved_view.dart';
import 'package:virthelm/core/models.dart';
import 'package:virthelm/core/profile_repository.dart';

class _Vault implements CredentialVault {
  final values = <String, ApiCredentials>{};

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('saved view JSON preserves supported local criteria', () {
    final view = SavedGuestView.create(
      name: ' Stopped containers ',
      search: ' cache ',
      status: 'stopped',
      kind: GuestKindFilter.lxc,
      node: ' pve2 ',
      tag: ' prod ',
      sort: GuestSort.memory,
    );
    final decoded = SavedGuestView.fromJson(view.toJson());
    expect(decoded.name, 'Stopped containers');
    expect(decoded.search, 'cache');
    expect(decoded.status, 'stopped');
    expect(decoded.kind, GuestKindFilter.lxc);
    expect(decoded.node, 'pve2');
    expect(decoded.tag, 'prod');
    expect(decoded.sort, GuestSort.memory);
    expect(decoded.id, view.id);
  });

  test('older saved views without a tag remain compatible', () {
    final decoded = SavedGuestView.fromJson({
      'id': 'legacy',
      'name': 'Legacy',
      'search': '',
      'status': 'all',
      'kind': 'all',
      'node': null,
      'sort': 'favorites',
    });
    expect(decoded.tag, isNull);
  });

  test('saved view rejects unsupported or oversized persisted values', () {
    expect(
      () => SavedGuestView.create(name: ''),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => SavedGuestView.create(
        name: 'A',
        search: List.filled(maxSavedGuestSearchLength + 1, 'x').join(),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => SavedGuestView.create(
        name: 'A',
        tag: List.filled(maxSavedGuestTagLength + 1, 'x').join(),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => SavedGuestView.fromJson({
        'id': 'bad',
        'name': 'Bad',
        'search': '',
        'status': 'destroyed',
        'kind': 'all',
        'sort': 'name',
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'repository isolates, updates and deletes profile-scoped views',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = ProfileRepository(prefs, _Vault());
      final a = ConnectionProfile.create(
        name: 'A',
        address: 'https://a.example',
      );
      final b = ConnectionProfile.create(
        name: 'B',
        address: 'https://b.example',
      );
      const credentials = ApiCredentials(
        tokenId: 'me@pve!test',
        secret: 'secret',
      );
      await repo.save(a, credentials);
      await repo.save(b, credentials);

      final initial = SavedGuestView.create(
        name: 'Stopped',
        status: 'stopped',
        kind: GuestKindFilter.lxc,
      );
      await repo.saveGuestView(a.id, initial);
      await repo.saveGuestView(
        b.id,
        SavedGuestView.create(name: 'Running', status: 'running'),
      );
      expect(repo.readGuestViews(a.id).single.name, 'Stopped');
      expect(repo.readGuestViews(b.id).single.name, 'Running');

      await repo.saveGuestView(
        a.id,
        SavedGuestView.create(
          name: ' stopped ',
          status: 'running',
          sort: GuestSort.cpu,
        ),
      );
      final updated = repo.readGuestViews(a.id);
      expect(updated, hasLength(1));
      expect(updated.single.id, initial.id);
      expect(updated.single.status, 'running');
      expect(updated.single.sort, GuestSort.cpu);

      await repo.delete(a.id);
      expect(repo.readGuestViews(a.id), isEmpty);
      expect(repo.readGuestViews(b.id).single.name, 'Running');
    },
  );

  test(
    'repository ignores malformed rows and enforces the view limit',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = ProfileRepository(prefs, _Vault());
      final profile = ConnectionProfile.create(
        name: 'Lab',
        address: 'https://pve.local',
      );
      const credentials = ApiCredentials(
        tokenId: 'me@pve!test',
        secret: 'secret',
      );
      await repo.save(profile, credentials);
      await prefs.setString(
        'guest_saved_views_v1',
        jsonEncode({
          profile.id: [
            {'name': 'missing id'},
            SavedGuestView.create(name: 'Valid').toJson(),
          ],
        }),
      );
      expect(repo.readGuestViews(profile.id).single.name, 'Valid');

      await prefs.remove('guest_saved_views_v1');
      for (var index = 0; index < maxSavedGuestViews; index++) {
        await repo.saveGuestView(
          profile.id,
          SavedGuestView.create(name: 'View $index'),
        );
      }
      expect(repo.readGuestViews(profile.id), hasLength(maxSavedGuestViews));
      await expectLater(
        repo.saveGuestView(
          profile.id,
          SavedGuestView.create(name: 'One too many'),
        ),
        throwsStateError,
      );
    },
  );

  test(
    'profile deletion removes malformed local guest metadata roots',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = ProfileRepository(prefs, _Vault());
      final profile = ConnectionProfile.create(
        name: 'Lab',
        address: 'https://pve.local',
      );
      const credentials = ApiCredentials(
        tokenId: 'me@pve!test',
        secret: 'secret',
      );
      await repo.save(profile, credentials);
      await prefs.setString(
        'guest_saved_views_v1',
        '{malformed private-search-metadata',
      );
      await prefs.setString(
        'guest_favorites_v1',
        jsonEncode(['wrong-root-shape']),
      );

      await repo.delete(profile.id);

      expect(prefs.getString('guest_saved_views_v1'), isNull);
      expect(prefs.getString('guest_favorites_v1'), isNull);
    },
  );
}
