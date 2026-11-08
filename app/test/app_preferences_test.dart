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

  test('malformed values use safe defaults', () async {
    final prefs = await SharedPreferences.getInstance();
    final repository = ProfileRepository(prefs, _Vault());
    expect(repository.themePreference, AppThemePreference.system);
    expect(repository.autoRefreshPreference, AutoRefreshPreference.off);
    expect(repository.showNodeMetrics, isTrue);
    expect(repository.highContrast, isFalse);
    expect(repository.reduceMotion, isFalse);

    await prefs.setString('ui_theme_v1', 'invalid');
    await prefs.setBool('ui_refresh_v1', true);
    await prefs.setString('ui_node_metrics_v1', 'invalid');
    await prefs.setString('ui_high_contrast_v1', 'invalid');
    await prefs.setString('ui_reduce_motion_v1', 'invalid');
    expect(repository.themePreference, AppThemePreference.system);
    expect(repository.autoRefreshPreference, AutoRefreshPreference.off);
    expect(repository.showNodeMetrics, isTrue);
    expect(repository.highContrast, isFalse);
    expect(repository.reduceMotion, isFalse);
  });

  test('settings persist without vault writes', () async {
    final prefs = await SharedPreferences.getInstance();
    final vault = _Vault();
    final repository = ProfileRepository(prefs, vault);
    await repository.setThemePreference(AppThemePreference.dark);
    await repository.setAutoRefreshPreference(
      AutoRefreshPreference.every60Seconds,
    );
    await repository.setShowNodeMetrics(false);
    await repository.setHighContrast(true);
    await repository.setReduceMotion(true);

    final reloaded = ProfileRepository(prefs, vault);
    expect(reloaded.themePreference, AppThemePreference.dark);
    expect(
      reloaded.autoRefreshPreference,
      AutoRefreshPreference.every60Seconds,
    );
    expect(reloaded.showNodeMetrics, isFalse);
    expect(reloaded.highContrast, isTrue);
    expect(reloaded.reduceMotion, isTrue);
    expect(vault.writes, 0);
  });

  test('controller loads and updates persisted local preferences', () async {
    final prefs = await SharedPreferences.getInstance();
    final repository = ProfileRepository(prefs, _Vault());
    await repository.setThemePreference(AppThemePreference.light);
    await repository.setHighContrast(true);
    final controller = AppController(repository: repository);
    addTearDown(controller.dispose);

    await controller.initialize();
    expect(controller.themePreference, AppThemePreference.light);
    expect(controller.highContrast, isTrue);
    expect(controller.reduceMotion, isFalse);
    await controller.setThemePreference(AppThemePreference.amoled);
    await controller.setAutoRefreshPreference(
      AutoRefreshPreference.every30Seconds,
    );
    await controller.setShowNodeMetrics(false);
    await controller.setHighContrast(false);
    await controller.setReduceMotion(true);
    expect(controller.themePreference, AppThemePreference.amoled);
    expect(
      controller.autoRefreshPreference,
      AutoRefreshPreference.every30Seconds,
    );
    expect(controller.showNodeMetrics, isFalse);
    expect(controller.highContrast, isFalse);
    expect(controller.reduceMotion, isTrue);
    expect(repository.showNodeMetrics, isFalse);
    expect(repository.highContrast, isFalse);
    expect(repository.reduceMotion, isTrue);
  });
}
