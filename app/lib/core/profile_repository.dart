import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

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

  List<ConnectionProfile> readProfiles() {
    final raw = _prefs.getString(_profilesKey);
    if (raw == null) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => ConnectionProfile.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  String? get activeId => _prefs.getString(_activeKey);

  Future<void> save(ConnectionProfile profile, ApiCredentials credentials) async {
    await vault.store(profile.id, credentials);
    try {
      final profiles = readProfiles();
      if (profiles.any((p) => p.id == profile.id)) {
        throw StateError('Profile already exists');
      }
      final saved = await _prefs.setString(
        _profilesKey,
        jsonEncode([...profiles, profile].map((e) => e.toJson()).toList()),
      );
      if (!saved) throw StateError('Could not store profile metadata.');
      await setActive(profile.id);
    } catch (_) {
      await vault.remove(profile.id);
      rethrow;
    }
  }

  Future<void> setActive(String? id) async {
    if (id == null) {
      await _prefs.remove(_activeKey);
    } else {
      await _prefs.setString(_activeKey, id);
    }
  }

  Future<void> delete(String id) async {
    final remaining = readProfiles().where((p) => p.id != id).toList();
    // Delete the encrypted token first; failure stops profile removal.
    await vault.remove(id);
    await _prefs.setString(
      _profilesKey,
      jsonEncode(remaining.map((p) => p.toJson()).toList()),
    );
    if (activeId == id) {
      await setActive(remaining.isEmpty ? null : remaining.first.id);
    }
  }
}
