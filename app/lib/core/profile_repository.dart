import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'alert_rules.dart';
import 'app_preferences.dart';
import 'foreground_notifications.dart';
import 'guest_saved_view.dart';
import 'incident_history.dart';
import 'models.dart';
import 'offline_inventory.dart';
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
  static const _thresholdRulesKey = 'foreground_threshold_rules_v1';
  static const _incidentHistoryKey = 'incident_history_v1';
  static const _foregroundNotificationPolicyKey =
      'foreground_notification_policy_v1';
  static const _foregroundNotificationStateKey =
      'foreground_notification_state_v1';
  static const _notificationLockScreenPrivacyKey =
      'notification_lock_screen_privacy_v1';
  static const _themeKey = 'ui_theme_v1';
  static const _refreshKey = 'ui_refresh_v1';
  static const _nodeMetricsKey = 'ui_node_metrics_v1';
  static const _highContrastKey = 'ui_high_contrast_v1';
  static const _reduceMotionKey = 'ui_reduce_motion_v1';
  static const _offlineEnabledPrefix = 'offline_counts_enabled_v1:';
  static const _offlineCountsPrefix = 'offline_counts_v1:';
  static const _offlineInventoryEnabledPrefix =
      'offline_inventory_enabled_v1:';
  static const _offlineInventoryPrefix = 'offline_inventory_v1:';
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

  String? _storedString(String key) {
    final value = _prefs.get(key);
    return value is String ? value : null;
  }

  List<ConnectionProfile> readProfiles() {
    final raw = _storedString(_profilesKey);
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

  String? get activeId => _storedString(_activeKey);

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

  bool get highContrast {
    final raw = _prefs.get(_highContrastKey);
    return raw is bool ? raw : false;
  }

  bool get reduceMotion {
    final raw = _prefs.get(_reduceMotionKey);
    return raw is bool ? raw : false;
  }

  IncidentNotificationLockScreenPrivacy get notificationLockScreenPrivacy =>
      incidentNotificationLockScreenPrivacyFromStorage(
        _prefs.get(_notificationLockScreenPrivacyKey),
      );

  Future<void> setNotificationLockScreenPrivacy(
    IncidentNotificationLockScreenPrivacy value,
  ) => _mutate(() async {
    if (!await _prefs.setString(
      _notificationLockScreenPrivacyKey,
      value.name,
    )) {
      throw StateError('Could not save notification privacy preference.');
    }
  });

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

  Future<void> setHighContrast(bool value) => _mutate(() async {
    if (!await _prefs.setBool(_highContrastKey, value)) {
      throw StateError('Could not save contrast preference.');
    }
  });

  Future<void> setReduceMotion(bool value) => _mutate(() async {
    if (!await _prefs.setBool(_reduceMotionKey, value)) {
      throw StateError('Could not save motion preference.');
    }
  });

  ForegroundNotificationPolicy readForegroundNotificationPolicy(
    String profileId,
  ) {
    final raw = _readProfileScopedJsonRoot(
      _foregroundNotificationPolicyKey,
    )[profileId];
    if (raw is! Map) return const ForegroundNotificationPolicy();
    try {
      return ForegroundNotificationPolicy.fromJson(
        Map<String, dynamic>.from(raw),
      );
    } on FormatException {
      return const ForegroundNotificationPolicy();
    }
  }

  DateTime? readLastForegroundNotificationAt(String profileId) {
    final raw = _readProfileScopedJsonRoot(
      _foregroundNotificationStateKey,
    )[profileId];
    if (raw is! String) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  Future<void> saveForegroundNotificationPolicy(
    String profileId,
    ForegroundNotificationPolicy policy,
  ) => _mutate(() async {
    if (!readProfiles().any((profile) => profile.id == profileId)) {
      throw StateError('Connection no longer exists.');
    }
    final validated = ForegroundNotificationPolicy.fromJson(policy.toJson());
    final root = _readProfileScopedJsonRoot(_foregroundNotificationPolicyKey);
    root[profileId] = validated.toJson();
    if (!await _prefs.setString(
      _foregroundNotificationPolicyKey,
      jsonEncode(root),
    )) {
      throw StateError('Could not save foreground notification policy.');
    }
  });

  Future<void> saveLastForegroundNotificationAt(
    String profileId,
    DateTime deliveredAt,
  ) => _mutate(() async {
    if (!readProfiles().any((profile) => profile.id == profileId)) return;
    final root = _readProfileScopedJsonRoot(_foregroundNotificationStateKey);
    root[profileId] = deliveredAt.toUtc().toIso8601String();
    if (!await _prefs.setString(
      _foregroundNotificationStateKey,
      jsonEncode(root),
    )) {
      throw StateError('Could not save foreground notification state.');
    }
  });

  Map<String, dynamic> _readProfileScopedJsonRoot(String key) {
    final raw = _storedString(key);
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

  Future<void> _clearProfileScopedJsonEntry(
    String key,
    String profileId,
    String label,
  ) async {
    final raw = _prefs.get(key);
    if (raw == null) return;
    Map<String, dynamic> root;
    try {
      final decoded = raw is String ? jsonDecode(raw) : null;
      if (decoded is! Map<String, dynamic>) {
        if (!await _prefs.remove(key)) {
          throw StateError('Could not clear $label.');
        }
        return;
      }
      root = Map<String, dynamic>.from(decoded);
    } catch (error) {
      if (error is StateError) rethrow;
      if (!await _prefs.remove(key)) {
        throw StateError('Could not clear $label.');
      }
      return;
    }
    if (!root.containsKey(profileId)) return;
    root.remove(profileId);
    final saved = root.isEmpty
        ? await _prefs.remove(key)
        : await _prefs.setString(key, jsonEncode(root));
    if (!saved) throw StateError('Could not clear $label.');
  }

  Future<void> _clearForegroundNotificationMetadata(String profileId) async {
    await _clearProfileScopedJsonEntry(
      _foregroundNotificationPolicyKey,
      profileId,
      'foreground notification policy',
    );
    await _clearProfileScopedJsonEntry(
      _foregroundNotificationStateKey,
      profileId,
      'foreground notification state',
    );
  }

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

  String _offlineInventoryEnabledKey(String id) =>
      '$_offlineInventoryEnabledPrefix$id';
  String _offlineInventoryKey(String id) => '$_offlineInventoryPrefix$id';

  bool offlineInventoryEnabled(String profileId) =>
      _prefs.get(_offlineInventoryEnabledKey(profileId)) == true;

  OfflineInventorySnapshot? readOfflineInventory(
    String profileId, {
    DateTime? now,
  }) {
    if (!offlineInventoryEnabled(profileId) ||
        !readProfiles().any((profile) => profile.id == profileId)) {
      return null;
    }
    final raw = _prefs.get(_offlineInventoryKey(profileId));
    if (raw is! String ||
        raw.length > maxOfflineInventorySerializedBytes) {
      return null;
    }
    try {
      return OfflineInventorySnapshot.fromJson(jsonDecode(raw), now: now);
    } catch (_) {
      return null;
    }
  }

  Future<void> setOfflineInventoryEnabled(String profileId, bool value) =>
      _mutate(() async {
        if (!readProfiles().any((profile) => profile.id == profileId)) {
          throw StateError('Connection no longer exists.');
        }
        if (value) {
          if (!await _prefs.setBool(_offlineInventoryEnabledKey(profileId), true)) {
            throw StateError('Could not enable offline inventory.');
          }
        } else {
          await _clearOfflineInventory(profileId);
          if (!await _prefs.remove(_offlineInventoryEnabledKey(profileId))) {
            throw StateError('Could not disable offline inventory.');
          }
        }
      });

  Future<void> saveOfflineInventory(
    String profileId,
    OfflineInventorySnapshot snapshot,
  ) => _mutate(() async {
    if (!offlineInventoryEnabled(profileId) ||
        !readProfiles().any((profile) => profile.id == profileId) ||
        OfflineInventorySnapshot.fromJson(snapshot.toJson()) == null) {
      return;
    }
    final raw = jsonEncode(snapshot.toJson());
    if (raw.length > maxOfflineInventorySerializedBytes) {
      await _clearOfflineInventory(profileId);
      return;
    }
    if (!await _prefs.setString(_offlineInventoryKey(profileId), raw)) {
      throw StateError('Could not save offline inventory.');
    }
  });

  Future<void> clearOfflineInventory(String profileId) =>
      _mutate(() => _clearOfflineInventory(profileId));

  Future<void> _clearOfflineInventory(String profileId) async {
    if (!await _prefs.remove(_offlineInventoryKey(profileId))) {
      throw StateError('Could not clear offline inventory.');
    }
  }

  List<ForegroundThresholdAlertRule> readThresholdAlertRules(String profileId) {
    final raw = _storedString(_thresholdRulesKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return [];
      final items = decoded[profileId];
      if (items is! List) return [];
      final rules = <ForegroundThresholdAlertRule>[];
      final ids = <String>{};
      for (final item in items) {
        if (item is! Map) continue;
        try {
          final rule = ForegroundThresholdAlertRule.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (!ids.add(rule.id)) continue;
          rules.add(rule);
          if (rules.length == maxForegroundThresholdRules) break;
        } on FormatException {
          continue;
        }
      }
      return List.unmodifiable(rules);
    } catch (_) {
      return [];
    }
  }

  Future<void> saveThresholdAlertRule(
    String profileId,
    ForegroundThresholdAlertRule rule,
  ) => _mutate(() async {
    if (!readProfiles().any((profile) => profile.id == profileId)) {
      throw StateError('Connection no longer exists.');
    }
    final validated = ForegroundThresholdAlertRule.fromJson(rule.toJson());
    final root = _readThresholdRulesRoot();
    final rules = readThresholdAlertRules(profileId).toList();
    final index = rules.indexWhere((item) => item.id == validated.id);
    if (index >= 0) {
      rules[index] = validated;
    } else {
      if (rules.length >= maxForegroundThresholdRules) {
        throw StateError('Foreground threshold rule limit reached.');
      }
      rules.add(validated);
    }
    root[profileId] = rules.map((item) => item.toJson()).toList();
    final saved = await _prefs.setString(_thresholdRulesKey, jsonEncode(root));
    if (!saved) {
      throw StateError('Could not save foreground threshold rule.');
    }
  });

  Future<void> deleteThresholdAlertRule(String profileId, String ruleId) =>
      _mutate(() async {
        if (!readProfiles().any((profile) => profile.id == profileId)) {
          throw StateError('Connection no longer exists.');
        }
        final root = _readThresholdRulesRoot();
        final rules = readThresholdAlertRules(
          profileId,
        ).where((item) => item.id != ruleId).toList();
        if (rules.isEmpty) {
          root.remove(profileId);
        } else {
          root[profileId] = rules.map((item) => item.toJson()).toList();
        }
        final saved = root.isEmpty
            ? await _prefs.remove(_thresholdRulesKey)
            : await _prefs.setString(_thresholdRulesKey, jsonEncode(root));
        if (!saved) {
          throw StateError('Could not delete foreground threshold rule.');
        }
      });

  Map<String, dynamic> _readThresholdRulesRoot() {
    final raw = _storedString(_thresholdRulesKey);
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

  Future<void> _clearThresholdAlertRules(String profileId) async {
    final raw = _prefs.get(_thresholdRulesKey);
    if (raw == null) return;
    Map<String, dynamic> root;
    try {
      final decoded = raw is String ? jsonDecode(raw) : null;
      if (decoded is! Map<String, dynamic>) {
        final removed = await _prefs.remove(_thresholdRulesKey);
        if (!removed) {
          throw StateError('Could not clear foreground threshold rules.');
        }
        return;
      }
      root = Map<String, dynamic>.from(decoded);
    } catch (error) {
      if (error is StateError) rethrow;
      final removed = await _prefs.remove(_thresholdRulesKey);
      if (!removed) {
        throw StateError('Could not clear foreground threshold rules.');
      }
      return;
    }
    if (!root.containsKey(profileId)) return;
    root.remove(profileId);
    final saved = root.isEmpty
        ? await _prefs.remove(_thresholdRulesKey)
        : await _prefs.setString(_thresholdRulesKey, jsonEncode(root));
    if (!saved) {
      throw StateError('Could not clear foreground threshold rules.');
    }
  }

  List<IncidentHistoryEntry> readIncidentHistory(String profileId) {
    final raw = _storedString(_incidentHistoryKey);
    if (raw == null) return const <IncidentHistoryEntry>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return const <IncidentHistoryEntry>[];
      }
      final items = decoded[profileId];
      if (items is! List) return const <IncidentHistoryEntry>[];
      final entries = <IncidentHistoryEntry>[];
      final ids = <String>{};
      for (final item in items) {
        if (item is! Map) continue;
        try {
          final entry = IncidentHistoryEntry.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (!ids.add(entry.occurrenceId)) continue;
          entries.add(entry);
          if (entries.length == maxPersistedIncidentHistory) break;
        } on FormatException {
          continue;
        }
      }
      entries.sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
      return List<IncidentHistoryEntry>.unmodifiable(entries);
    } catch (_) {
      return const <IncidentHistoryEntry>[];
    }
  }

  Future<void> saveIncidentHistory(
    String profileId,
    Iterable<IncidentHistoryEntry> entries,
  ) => _mutate(() async {
    // A queued best-effort history save must never resurrect metadata for a
    // connection that was deleted while the write was waiting.
    if (!readProfiles().any((profile) => profile.id == profileId)) return;
    final root = _readIncidentHistoryRoot();
    final validated = <IncidentHistoryEntry>[];
    final ids = <String>{};
    for (final entry in entries) {
      try {
        final item = IncidentHistoryEntry.fromJson(entry.toJson());
        if (!ids.add(item.occurrenceId)) continue;
        validated.add(item);
        if (validated.length == maxPersistedIncidentHistory) break;
      } on FormatException {
        continue;
      }
    }
    if (validated.isEmpty) {
      root.remove(profileId);
    } else {
      root[profileId] = validated.map((entry) => entry.toJson()).toList();
    }
    final saved = root.isEmpty
        ? await _prefs.remove(_incidentHistoryKey)
        : await _prefs.setString(_incidentHistoryKey, jsonEncode(root));
    if (!saved) throw StateError('Could not save incident history.');
  });

  Map<String, dynamic> _readIncidentHistoryRoot() {
    final raw = _storedString(_incidentHistoryKey);
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

  Future<void> _clearIncidentHistory(String profileId) async {
    final raw = _prefs.get(_incidentHistoryKey);
    if (raw == null) return;
    Map<String, dynamic> root;
    try {
      final decoded = raw is String ? jsonDecode(raw) : null;
      if (decoded is! Map<String, dynamic>) {
        final removed = await _prefs.remove(_incidentHistoryKey);
        if (!removed) throw StateError('Could not clear incident history.');
        return;
      }
      root = Map<String, dynamic>.from(decoded);
    } catch (error) {
      if (error is StateError) rethrow;
      final removed = await _prefs.remove(_incidentHistoryKey);
      if (!removed) throw StateError('Could not clear incident history.');
      return;
    }
    if (!root.containsKey(profileId)) return;
    root.remove(profileId);
    final saved = root.isEmpty
        ? await _prefs.remove(_incidentHistoryKey)
        : await _prefs.setString(_incidentHistoryKey, jsonEncode(root));
    if (!saved) throw StateError('Could not clear incident history.');
  }

  Set<String> readGuestFavorites(String profileId) {
    final raw = _storedString(_favoritesKey);
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
    final raw = _storedString(_favoritesKey);
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
    final raw = _storedString(_guestViewsKey);
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
    final raw = _storedString(_guestViewsKey);
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
    final raw = _prefs.get(_guestViewsKey);
    if (raw == null) return;
    Map<String, dynamic> root;
    try {
      final decoded = raw is String ? jsonDecode(raw) : null;
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
    final raw = _prefs.get(_favoritesKey);
    if (raw == null) return;
    try {
      final decoded = raw is String ? jsonDecode(raw) : null;
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
        // Even a same-endpoint token/ACL change must invalidate old offline
        // observations before the credential/profile identity is replaced.
        await _clearOfflineOverview(profile.id);
        await _clearOfflineInventory(profile.id);
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

  /// User edits invalidate offline observations without rewriting an
  /// unchanged token.
  Future<void> updateConfigurationMetadata(ConnectionProfile profile) =>
      _mutate(() async {
        final profiles = readProfiles();
        final index = profiles.indexWhere((item) => item.id == profile.id);
        if (index < 0) throw StateError('Connection no longer exists.');
        await _clearOfflineOverview(profile.id);
        await _clearOfflineInventory(profile.id);
        await _writeProfiles([...profiles]..[index] = profile);
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
      await _clearThresholdAlertRules(id);
    } catch (_) {}
    try {
      await _clearIncidentHistory(id);
    } catch (_) {}
    try {
      await _clearForegroundNotificationMetadata(id);
    } catch (_) {}
    try {
      await _clearOfflineOverview(id);
      await _prefs.remove(_offlineEnabledKey(id));
    } catch (_) {}
    try {
      await _clearOfflineInventory(id);
      await _prefs.remove(_offlineInventoryEnabledKey(id));
    } catch (_) {}
    if (activeId == id) {
      await _setActive(remaining.isEmpty ? null : remaining.first.id);
    }
  });
}
