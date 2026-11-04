import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:virthelm/core/app_controller.dart';
import 'package:virthelm/core/app_preferences.dart';
import 'package:virthelm/core/models.dart';
import 'package:virthelm/core/profile_repository.dart';

class _Vault implements CredentialVault {
  int writes = 0;

  @override
  Future<void> store(String id, ApiCredentials credentials) async {
    writes++;
  }

  @override
  Future<ApiCredentials?> retrieve(String id) async => null;

  @override
  Future<void> remove(String id) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('local defaults and malformed values fail to safe preferences', () async {
    final prefs = await SharedPreferences.getInstance();
    final repository = ProfileRepository(prefs, _Vault());
    expect(repository.themePreference, AppThemePreference.system);
    expect(repository.autoRefreshPreference, AutoRefreshPreference.off);
    expect(repository.showNodeMetrics, isTrue);

    await prefs.setString('ui_theme_v1', 'invalid');
    await prefs.setBool('ui_refresh_v1', true);
    await prefs.setString('ui_node_metrics_v1', 'invalid');
    expect(repository.themePreference, AppThemePreference.system);
    expect(repository.autoRefreshPreference, AutoRefreshPreference.off);
    expect(repository.showNodeMetrics, isTrue);
  });

  test('preferences persist across repositories without vault operations', () async {
    final prefs = await SharedPreferences.getInstance();
    final vault = _Vault();
    final repository = ProfileRepository(prefs, vault);
    await repository.setThemePreference(AppThemePreference.dark);
    await repository.setAutoRefreshPreference(
      AutoRefreshPreference.every60Seconds,
    );
    await repository.setShowNodeMetrics(false);

    final reloaded = ProfileRepository(prefs, vault);
    expect(reloaded.themePreference, AppThemePreference.dark);
    expect(
      reloaded.autoRefreshPreference,
      AutoRefreshPreference.every60Seconds,
    );
    expect(reloaded.showNodeMetrics, isFalse);
    expect(vault.writes, 0);
  });

  test('controller loads and updates persisted local preferences', () async {
    final prefs = await SharedPreferences.getInstance();
    final repository = ProfileRepository(prefs, _Vault());
    await repository.setThemePreference(AppThemePreference.light);
    final controller = AppController(repository: repository);
    addTearDown(controller.dispose);

    await controller.initialize();
    expect(controller.themePreference, AppThemePreference.light);
    await controller.setThemePreference(AppThemePreference.dark);
    await controller.setAutoRefreshPreference(
      AutoRefreshPreference.every30Seconds,
    );
    await controller.setShowNodeMetrics(false);
    expect(controller.themePreference, AppThemePreference.dark);
    expect(
      controller.autoRefreshPreference,
      AutoRefreshPreference.every30Seconds,
    );
    expect(controller.showNodeMetrics, isFalse);
    expect(repository.showNodeMetrics, isFalse);
  });
}
