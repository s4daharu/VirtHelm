import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_preferences.dart';
import 'guest_saved_view.dart';
import 'models.dart';
import 'offline_overview.dart';

abstract class CredentialVault {
  Future<void> store(String id, ApiCredentials credentials);
  Future<ApiCredentials?> retrieve(String id);
  Future<void> remove(String id);
}

class SecureCredentialVault implements CredentialVault {
  SecureCredentialVault([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  String _key(String id) => 'virthelm:token:$id';

  @override
  Future<void> store(String id, ApiCredentials credentials) =>
      _storage.write(key: _key(id), value: credentials.encode());

  @override
  Future<ApiCredentials?> retrieve(String id) async {
    final value = await _storage.read(key: _key(id));
    return value == null ? null : ApiCredentials.decode(value);
  }

  @override
  Future<void> remove(String id) => _storage.delete(key: _key(id));
}

class ProfileRepository {
  ProfileRepository(this._prefs, this.vault);
  final SharedPreferences _prefs;
  final CredentialVault vault;

  static const _profilesKey = 'profile_metadata_v1';
  static const _activeKey = 'active_profile_v1';
  static const _favoritesKey = 'guest_favorites_v1';
  static const _guestViewsKey = 'guest_saved_views_v1';
  static const _themeKey = 'ui_theme_v1';
  static const _refreshKey = 'ui_refresh_v1';
  static const _nodeMetricsKey = 'ui_node_metrics_v1';
  static const _offlineEnabledPrefix = 'offline_counts_enabled_v1:';
  static const _offlineCountsPrefix = 'offline_counts_v1:';
  Future<void> _writes = Future<void>.value();

  // A vault operation can yield before metadata is written. Serialize local
  // mutations so overlapping saves/deletes cannot overwrite a stale snapshot.
  Future<T> _mutate<T>(Future<T> Function() operation) {
    final result = _writes.then((_) => operation());
    _writes = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  List<ConnectionProfile> readProfiles() {
    final raw = _prefs.getString(_profilesKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final profiles = <ConnectionProfile>[];
      final ids = <String>{};
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          final profile = ConnectionProfile.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (profile.id.trim().isEmpty ||
              profile.name.trim().isEmpty ||
              !ids.add(profile.id)) {
            continue;
          }
          profiles.add(profile);
        } catch (_) {
          // Corrupt non-secret metadata must not prevent access to valid
          // neighboring profiles or block the operator from adding a new one.
        }
      }
      return List.unmodifiable(profiles);
    } catch (_) {
      return [];
    }
  }

  String? get activeId => _prefs.getString(_activeKey);

  AppThemePreference get themePreference {
    final raw = _prefs.get(_themeKey);
    for (final value in AppThemePreference.values) {
      if (raw == value.name) return value;
    }
    return AppThemePreference.system;
  }

  AutoRefreshPreference get autoRefreshPreference {
    final raw = _prefs.get(_refreshKey);
    for (final value in AutoRefreshPreference.values) {
      if (raw == value.name) return value;
    }
    return AutoRefreshPreference.off;
  }

  bool get showNodeMetrics {
    final raw = _prefs.get(_nodeMetricsKey);
    return raw is bool ? raw : true;
  }

  Future<void> setThemePreference(AppThemePreference value) =>
      _mutate(() async {
        if (!await _prefs.setString(_themeKey, value.name)) {
          throw StateError('Could not save appearance preference.');
        }
      });

  Future<void> setAutoRefreshPreference(AutoRefreshPreference value) =>
      _mutate(() async {
        if (!await _prefs.setString(_refreshKey, value.name)) {
          throw StateError('Could not save refresh preference.');
        }
      });

  Future<void> setShowNodeMetrics(bool value) => _mutate(() async {
    if (!await _prefs.setBool(_nodeMetricsKey, value)) {
      throw StateError('Could not save display preference.');
    }
  });

  // Counts-only opt-in cache. No server names, resource IDs, endpoints,
  // credentials, task logs, raw responses, or live authorization flags.
  String _offlineEnabledKey(String id) => '$_offlineEnabledPrefix$id';
  String _offlineCountsKey(String id) => '$_offlineCountsPrefix$id';

  bool offlineOverviewEnabled(String profileId) =>
      _prefs.get(_offlineEnabledKey(profileId)) == true;

  OfflineOverview? readOfflineOverview(String profileId, {DateTime? now}) {
    if (!offlineOverviewEnabled(profileId) ||
        !readProfiles().any((profile) => profile.id == profileId)) {
      return null;
    }
    final raw = _prefs.get(_offlineCountsKey(profileId));
    if (raw is! String || raw.length > 512) return null;
    try {
      return OfflineOverview.fromJson(jsonDecode(raw), now: now);
    } catch (_) {
      return null;
    }
  }

  Future<void> setOfflineOverviewEnabled(String profileId, bool value) =>
      _mutate(() async {
        if (!readProfiles().any((profile) => profile.id == profileId)) {
          throw StateError('Connection no longer exists.');
        }
        if (value) {
          if (!await _prefs.setBool(_offlineEnabledKey(profileId), true)) {
            throw StateError('Could not enable offline overview.');
          }
        } else {
          // Purge data before removing consent; a failure cannot claim the
          // cached data has been erased.
          await _clearOfflineOverview(profileId);
          if (!await _prefs.remove(_offlineEnabledKey(profileId))) {
            throw StateError('Could not disable offline overview.');
          }
        }
      });

  Future<void> saveOfflineOverview(String profileId, OfflineOverview summary) =>
      _mutate(() async {
        if (!offlineOverviewEnabled(profileId) ||
            !readProfiles().any((profile) => profile.id == profileId) ||
            OfflineOverview.fromJson(summary.toJson()) == null) {
          return;
        }
        final raw = jsonEncode(summary.toJson());
        if (raw.length > 512) return;
        if (!await _prefs.setString(_offlineCountsKey(profileId), raw)) {
          throw StateError('Could not save offline overview.');
        }
      });

  Future<void> clearOfflineOverview(String profileId) =>
      _mutate(() => _clearOfflineOverview(profileId));

  Future<void> _clearOfflineOverview(String profileId) async {
    if (!await _prefs.remove(_offlineCountsKey(profileId))) {
      throw StateError('Could not clear offline overview.');
    }
  }

  Set<String> readGuestFavorites(String profileId) {
    final raw = _prefs.getString(_favoritesKey);
    if (raw == null) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return <String>{};
      final values = decoded[profileId];
      if (values is! List) return <String>{};
      return values.whereType<String>().toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> setGuestFavorite(
    String profileId,
    String guestKey,
    bool favorite,
  ) => _mutate(() async {
    if (!readProfiles().any((profile) => profile.id == profileId)) {
      throw StateError('Connection no longer exists.');
    }
    final raw = _prefs.getString(_favoritesKey);
    final decoded = <String, dynamic>{};
    if (raw != null) {
      try {
        final value = jsonDecode(raw);
        if (value is Map<String, dynamic>) decoded.addAll(value);
      } catch (_) {}
    }
    final favorites = readGuestFavorites(profileId);
    if (favorite) {
      favorites.add(guestKey);
    } else {
      favorites.remove(guestKey);
    }
    if (favorites.isEmpty) {
      decoded.remove(profileId);
    } else {
      final sorted = favorites.toList()..sort();
      decoded[profileId] = sorted;
    }
    final saved = decoded.isEmpty
        ? await _prefs.remove(_favoritesKey)
        : await _prefs.setString(_favoritesKey, jsonEncode(decoded));
    if (!saved) throw StateError('Could not update guest favorites.');
  });

  List<SavedGuestView> readGuestViews(String profileId) {
    final raw = _prefs.getString(_guestViewsKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return [];
      final items = decoded[profileId];
      if (items is! List) return [];
      final views = <SavedGuestView>[];
      final ids = <String>{};
      final names = <String>{};
      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        try {
          final view = SavedGuestView.fromJson(item);
          final normalizedName = view.name.toLowerCase();
          if (!ids.add(view.id) || !names.add(normalizedName)) continue;
          views.add(view);
          if (views.length == maxSavedGuestViews) break;
        } on FormatException {
          continue;
        }
      }
      return List.unmodifiable(views);
    } catch (_) {
      return [];
    }
  }

  Future<void> saveGuestView(String profileId, SavedGuestView view) =>
      _mutate(() async {
        if (!readProfiles().any((profile) => profile.id == profileId)) {
          throw StateError('Connection no longer exists.');
        }
        final validated = SavedGuestView.fromJson(view.toJson());
        final root = _readGuestViewsRoot();
        final views = readGuestViews(profileId).toList();
        final idIndex = views.indexWhere((item) => item.id == validated.id);
        final nameIndex = views.indexWhere(
          (item) => item.name.toLowerCase() == validated.name.toLowerCase(),
        );
        if (idIndex >= 0 && nameIndex >= 0 && idIndex != nameIndex) {
          throw StateError('A saved view already uses this name.');
        }
        final index = idIndex >= 0 ? idIndex : nameIndex;
        final replacement = index >= 0 && idIndex < 0
            ? validated.withId(views[index].id)
            : validated;
        if (index >= 0) {
          views[index] = replacement;
        } else {
          if (views.length >= maxSavedGuestViews) {
            throw StateError('Saved view limit reached.');
          }
          views.add(replacement);
        }
        root[profileId] = views.map((item) => item.toJson()).toList();
        final saved = await _prefs.setString(_guestViewsKey, jsonEncode(root));
        if (!saved) throw StateError('Could not save guest view.');
      });

  Future<void> deleteGuestView(String profileId, String viewId) =>
      _mutate(() async {
        if (!readProfiles().any((profile) => profile.id == profileId)) {
          throw StateError('Connection no longer exists.');
        }
        final root = _readGuestViewsRoot();
        final views = readGuestViews(
          profileId,
        ).where((item) => item.id != viewId).toList();
        if (views.isEmpty) {
          root.remove(profileId);
        } else {
          root[profileId] = views.map((item) => item.toJson()).toList();
        }
        final saved = root.isEmpty
            ? await _prefs.remove(_guestViewsKey)
            : await _prefs.setString(_guestViewsKey, jsonEncode(root));
        if (!saved) throw StateError('Could not delete guest view.');
      });

  Map<String, dynamic> _readGuestViewsRoot() {
    final raw = _prefs.getString(_guestViewsKey);
    if (raw == null) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic>
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> _clearGuestViews(String profileId) async {
    final raw = _prefs.getString(_guestViewsKey);
    if (raw == null) return;
    Map<String, dynamic> root;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        final removed = await _prefs.remove(_guestViewsKey);
        if (!removed) throw StateError('Could not clear guest views.');
        return;
      }
      root = decoded;
    } catch (error) {
      if (error is StateError) rethrow;
      final removed = await _prefs.remove(_guestViewsKey);
      if (!removed) throw StateError('Could not clear guest views.');
      return;
    }
    if (!root.containsKey(profileId)) return;
    root.remove(profileId);
    final saved = root.isEmpty
        ? await _prefs.remove(_guestViewsKey)
        : await _prefs.setString(_guestViewsKey, jsonEncode(root));
    if (!saved) throw StateError('Could not clear guest views.');
  }

  Future<void> clearGuestFavorites(String profileId) =>
      _mutate(() => _clearGuestFavorites(profileId));

  Future<void> _clearGuestFavorites(String profileId) async {
    final raw = _prefs.getString(_favoritesKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        final removed = await _prefs.remove(_favoritesKey);
        if (!removed) throw StateError('Could not clear guest favorites.');
        return;
      }
      if (!decoded.containsKey(profileId)) return;
      decoded.remove(profileId);
      final saved = decoded.isEmpty
          ? await _prefs.remove(_favoritesKey)
          : await _prefs.setString(_favoritesKey, jsonEncode(decoded));
      if (!saved) throw StateError('Could not clear guest favorites.');
    } catch (error) {
      if (error is StateError) rethrow;
      final removed = await _prefs.remove(_favoritesKey);
      if (!removed) throw StateError('Could not clear guest favorites.');
    }
  }

  Future<void> _writeProfiles(List<ConnectionProfile> profiles) async {
    final saved = await _prefs.setString(
      _profilesKey,
      jsonEncode(profiles.map((profile) => profile.toJson()).toList()),
    );
    if (!saved) throw StateError('Could not store profile metadata.');
  }

  Future<void> save(ConnectionProfile profile, ApiCredentials credentials) =>
      _mutate(() async {
        final profiles = readProfiles();
        if (profiles.any((item) => item.id == profile.id)) {
          throw StateError('Profile already exists');
        }
        final previousActive = activeId;
        try {
          await vault.store(profile.id, credentials);
          await _writeProfiles([...profiles, profile]);
          await _setActive(profile.id);
        } catch (error, stackTrace) {
          // Best-effort rollback keeps ordinary metadata and encrypted secrets
          // from becoming intentionally divergent after a partial local write.
          try {
            await _writeProfiles(profiles);
          } catch (_) {}
          try {
            await _setActive(previousActive);
          } catch (_) {}
          try {
            await vault.remove(profile.id);
          } catch (_) {}
          Error.throwWithStackTrace(error, stackTrace);
        }
      });

  Future<void> update(ConnectionProfile profile, ApiCredentials credentials) =>
      _mutate(() async {
        final profiles = readProfiles();
        final index = profiles.indexWhere((item) => item.id == profile.id);
        if (index < 0) {
          throw StateError('Connection no longer exists.');
        }
        final previousCredentials = await vault.retrieve(profile.id);
        final nextProfiles = [...profiles]..[index] = profile;
        // Even a same-endpoint token/ACL change must invalidate old counts.
        await _clearOfflineOverview(profile.id);
        try {
          await vault.store(profile.id, credentials);
          await _writeProfiles(nextProfiles);
        } catch (error, stackTrace) {
          try {
            if (previousCredentials == null) {
              await vault.remove(profile.id);
            } else {
              await vault.store(profile.id, previousCredentials);
            }
          } catch (_) {}
          try {
            await _writeProfiles(profiles);
          } catch (_) {}
          Error.throwWithStackTrace(error, stackTrace);
        }
      });

  Future<void> updateMetadata(ConnectionProfile profile) => _mutate(() async {
    final profiles = readProfiles();
    final index = profiles.indexWhere((item) => item.id == profile.id);
    if (index < 0) {
      throw StateError('Connection no longer exists.');
    }
    final nextProfiles = [...profiles]..[index] = profile;
    await _writeProfiles(nextProfiles);
  });

  Future<void> setActive(String? id) => _mutate(() => _setActive(id));

  Future<void> _setActive(String? id) async {
    final saved = id == null
        ? await _prefs.remove(_activeKey)
        : await _prefs.setString(_activeKey, id);
    if (!saved) throw StateError('Could not update the active profile.');
  }

  Future<void> delete(String id) => _mutate(() async {
    final remaining = readProfiles()
        .where((profile) => profile.id != id)
        .toList();
    // Delete the encrypted token first; failure stops profile removal.
    await vault.remove(id);
    await _writeProfiles(remaining);
    // Favorites contain no credentials and are secondary metadata. Once the
    // token and profile metadata are gone, stale favorite cleanup must not
    // turn a successful security-sensitive deletion into a reported failure.
    try {
      await _clearGuestFavorites(id);
    } catch (_) {}
    try {
      await _clearGuestViews(id);
    } catch (_) {}
    try {
      await _clearOfflineOverview(id);
      await _prefs.remove(_offlineEnabledKey(id));
    } catch (_) {}
    if (activeId == id) {
      await _setActive(remaining.isEmpty ? null : remaining.first.id);
    }
  });
}
