#!/usr/bin/env python3
"""Offline source structure/security assertions; not a replacement for Flutter tests."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
required = [
  'app/pubspec.yaml','app/pubspec.lock','app/lib/main.dart','app/lib/core/models.dart',
  'app/lib/core/profile_repository.dart','app/lib/core/pve_api.dart',
  'app/lib/core/app_controller.dart','app/lib/core/app_preferences.dart',
  'app/lib/core/offline_overview.dart','app/lib/core/device_connectivity.dart',
  'app/lib/core/guest_list_filter.dart','app/lib/core/task_history_filter.dart',
  'app/lib/core/guest_saved_view.dart','app/lib/core/incident_center.dart',
  'app/lib/ui/theme.dart',
  'app/lib/ui/connect_page.dart','app/lib/ui/shell.dart',
  'app/lib/ui/guest_page.dart','app/lib/ui/node_page.dart','app/lib/ui/storage_page.dart',
  'app/lib/ui/incident_center_tab.dart','app/lib/ui/task_details_page.dart',
  'app/test/models_test.dart',
  'app/test/controller_test.dart','app/test/pve_api_test.dart',
  'app/test/widget_test.dart','app/test/pve_tls_test.dart',
  'app/test/incident_center_test.dart',
  'app/test/guest_list_filter_test.dart','app/test/task_history_filter_test.dart',
  'app/test/saved_guest_view_test.dart',
  'app/test/app_preferences_test.dart','app/test/offline_overview_test.dart',
  'scripts/bootstrap_android.sh','scripts/harden_android.py',
  'scripts/check_android_generated.py',
  'docs/37-implementation-m1.md','docs/38-implementation-m2-read-cockpit.md',
  'docs/39-implementation-audit.md','docs/40-profile-tls-option.md',
  'docs/41-cross-check-audit.md','docs/42-merge-readiness-cross-check.md',
  'docs/44-implementation-m2-saved-guest-views.md',
  'docs/45-full-implementation-cross-check.md',
  'docs/46-implementation-p0-profile-editing.md',
  'docs/47-implementation-p0-server-version.md',
  'docs/48-implementation-p0-read-retries.md',
  'docs/49-whole-repository-audit-2026-11-04.md',
  'docs/50-implementation-p0-local-preferences.md',
  'docs/51-implementation-p0-task-details.md',
  'docs/52-implementation-p0-transport-errors.md',
  'docs/53-implementation-p0-offline-overview.md',
   'docs/54-implementation-p0-android-connectivity.md',
   'docs/55-implementation-f09-task-log-pages.md',
   'docs/56-implementation-f09-task-history-filters.md',
   'docs/57-implementation-guest-io-counters.md',
   'docs/58-premerge-whole-repository-audit-2026-11-05.md',
   'docs/59-implementation-guest-rrd-history.md',
   'docs/60-implementation-tag-pool-browsing.md',
   'docs/61-implementation-node-rrd-history.md',
   'docs/62-whole-repository-cross-check-2026-11-06.md',
   'docs/63-implementation-storage-rrd-history.md',
   'docs/64-implementation-alert-incident-inbox.md']
assert all((root/p).is_file() for p in required), 'Required app source missing'
files = {p: (root/p).read_text(encoding='utf-8') for p in required}
assert '--platforms=android' in files['scripts/bootstrap_android.sh']
assert 'android:allowBackup' in files['scripts/harden_android.py']
assert 'android:usesCleartextTraffic' in files['scripts/harden_android.py']
assert 'android.permission.INTERNET' in files['scripts/harden_android.py']
assert 'minSdk = 26' in files['scripts/harden_android.py']
assert 'debug release signing' in files['scripts/harden_android.py']
assert 'PVEAPIToken=' in files['app/lib/core/models.dart']
assert 'options.followRedirects = false' in files['app/lib/core/pve_api.dart']
assert 'SecureCredentialVault' in files['app/lib/core/profile_repository.dart']
assert 'Future<void> update(ConnectionProfile profile' in files['app/lib/core/profile_repository.dart']
assert 'Future<void> updateConnection' in files['app/lib/core/app_controller.dart']
assert 'lastServerVersion' in files['app/lib/core/models.dart']
assert 'Future<void> updateMetadata' in files['app/lib/core/profile_repository.dart']
assert "last observed" in files['app/lib/ui/shell.dart']
assert 'mayHaveExecuted' in files['app/lib/core/pve_api.dart']
assert 'setThemePreference' in files['app/lib/core/app_controller.dart']
assert '_scheduleAutoRefresh' in files['app/lib/core/app_controller.dart']
assert 'setShowNodeMetrics' in files['app/lib/core/profile_repository.dart']
assert 'themeMode: switch' in files['app/lib/main.dart']
assert 'OfflineOverview.fromInventory' in files['app/lib/core/app_controller.dart']
assert 'Keep offline overview counts' in files['app/lib/ui/shell.dart']
assert 'offlineOverviewEnabled' in files['app/lib/core/profile_repository.dart']
assert 'enum PveTransportFailure' in files['app/lib/core/models.dart']
assert '_transportFailure' in files['app/lib/core/pve_api.dart']
assert "test('GET transport diagnoses show safe, distinct guidance'" in files['app/test/pve_api_test.dart']
assert '_shouldRetryRead' in files['app/lib/core/pve_api.dart']
assert 'attempt >= 2' in files['app/lib/core/pve_api.dart']
assert "test('transient POST failure is never automatically retried'" in files['app/test/pve_api_test.dart']
assert 'storageOverview' in files['app/lib/core/pve_api.dart']
assert 'recentTasks' in files['app/lib/core/pve_api.dart']
assert 'visibleServerTasks' in files['app/lib/ui/shell.dart']
assert '_guestByteCounter' in files['app/lib/core/models.dart']
assert 'Guest I/O counters' in files['app/lib/ui/guest_page.dart']
assert 'GuestMetricTimeframe' in files['app/lib/core/models.dart']
assert 'Future<GuestMetricSeries> guestMetrics' in files['app/lib/core/pve_api.dart']
assert "'cf': 'AVERAGE'" in files['app/lib/core/pve_api.dart']
assert 'inspectGuestMetrics' in files['app/lib/core/app_controller.dart']
controller = files['app/lib/core/app_controller.dart']
task_inspection = controller.split('Future<TaskInspection?> inspectTask', 1)[1].split('Future<GuestMetricSeries?> inspectGuestMetrics', 1)[0]
assert 'deviceNetworkState == DeviceNetworkState.unavailable' in task_inspection
assert '_recordAuthenticatedReadLoss' in controller
assert 'Performance history' in files['app/lib/ui/guest_page.dart']
assert 'NodeMetricTimeframe' in files['app/lib/core/models.dart']
assert 'Future<NodeMetricSeries> nodeMetrics' in files['app/lib/core/pve_api.dart']
assert "'/nodes/${_segment(normalizedNode)}/rrddata'" in files['app/lib/core/pve_api.dart']
assert 'inspectNodeMetrics' in files['app/lib/core/app_controller.dart']
assert 'class NodePage' in files['app/lib/ui/node_page.dart']
assert 'NodePage(' in files['app/lib/ui/shell.dart']
assert 'StorageMetricTimeframe' in files['app/lib/core/models.dart']
assert 'Future<StorageMetricSeries> storageMetrics' in files['app/lib/core/pve_api.dart']
assert "'/nodes/${_segment(normalizedNode)}/storage/'" in files['app/lib/core/pve_api.dart']
assert "'${_segment(normalizedStorage)}/rrddata'" in files['app/lib/core/pve_api.dart']
assert 'inspectStorageMetrics' in files['app/lib/core/app_controller.dart']
assert 'class StoragePage' in files['app/lib/ui/storage_page.dart']
assert 'StoragePage(' in files['app/lib/ui/shell.dart']
assert 'buildCockpitIncidents' in files['app/lib/core/incident_center.dart']
assert '_retainedServerTaskIncidents' in files['app/lib/core/app_controller.dart']
assert 'class IncidentCenterTab' in files['app/lib/ui/incident_center_tab.dart']
assert "label: 'Incidents'" in files['app/lib/ui/shell.dart']
assert 'INCIDENT DATA MAY BE STALE' in files['app/lib/ui/incident_center_tab.dart']
assert '_guestTags' in files['app/lib/core/models.dart']
assert 'final List<String> tags' in files['app/lib/core/models.dart']
assert 'String? tag' in files['app/lib/core/guest_list_filter.dart']
assert 'String? pool' in files['app/lib/core/guest_saved_view.dart']
assert "tooltip: 'Filter by tag'" in files['app/lib/ui/shell.dart']
assert "tooltip: 'Filter by pool'" in files['app/lib/ui/shell.dart']
assert '_currentSession' in files['app/lib/ui/guest_page.dart']
assert 'generation: generation' in files['app/lib/ui/shell.dart']
assert 'ServerTaskStateFilter' in files['app/lib/core/task_history_filter.dart']
assert 'Future<TaskLogResult> taskLog' in files['app/lib/core/pve_api.dart']
assert "'limit': 100" in files['app/lib/core/pve_api.dart']
assert 'generation == _generation' in files['app/lib/core/app_controller.dart']
assert 'connectionGeneration == widget.generation' in files['app/lib/ui/task_details_page.dart']
assert 'GuestAction.stop' in files['app/lib/core/app_controller.dart'] or 'GuestAction' in files['app/lib/core/app_controller.dart']
for p in (root/'app/lib').rglob('*.dart'):
    data = p.read_text(encoding='utf-8')
    # The sole exception is the profile-local, exact-origin native gateway.
    if 'badCertificateCallback' in data:
        assert p == root/'app/lib/core/pve_api.dart'
        assert 'if (profile.allowInvalidCertificates)' in data
        assert 'host == origin.host && port == origin.port' in data
    assert 'HttpOverrides.' not in data
    assert 'SecurityContext(withTrustedRoots: false)' not in data
assert 'this.allowInvalidCertificates = false' in files['app/lib/core/models.dart']
assert 'Disable certificate verification?' in files['app/lib/ui/connect_page.dart']
assert 'DeviceNetworkState.unavailable' in files['app/lib/core/app_controller.dart']
assert 'deviceNetworkChanges().listen' in files['app/lib/main.dart']
assert 'registerDefaultNetworkCallback' in (root/'scripts/android/MainActivity.kt').read_text()
assert 'TlsWarning' not in files['app/lib/ui/shell.dart']
assert 'TlsWarning' not in files['app/lib/ui/guest_page.dart']
print('App source smoke checks passed (not a Dart compile or device test).')
