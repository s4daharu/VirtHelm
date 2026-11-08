#!/usr/bin/env python3
"""Offline source structure/security assertions; not a replacement for Flutter tests."""
from pathlib import Path
import re
root = Path(__file__).resolve().parents[1]
required = [
  'app/pubspec.yaml','app/pubspec.lock','app/lib/main.dart','app/lib/core/models.dart',
  'app/lib/core/profile_repository.dart','app/lib/core/pve_api.dart',
  'app/lib/core/app_controller.dart','app/lib/core/app_preferences.dart',
  'app/lib/core/offline_overview.dart','app/lib/core/device_connectivity.dart',
  'app/lib/core/guest_list_filter.dart','app/lib/core/task_history_filter.dart',
  'app/lib/core/guest_saved_view.dart','app/lib/core/alert_rules.dart',
  'app/lib/core/incident_center.dart',
  'app/lib/ui/theme.dart',
  'app/lib/ui/components.dart',
  'app/lib/core/app_info.dart',
  'app/lib/ui/connect_page.dart','app/lib/ui/connections_page.dart','app/lib/ui/shell.dart',
  'app/lib/ui/guest_page.dart','app/lib/ui/node_page.dart','app/lib/ui/storage_page.dart',
  'app/lib/ui/alert_rules_page.dart','app/lib/ui/incident_center_tab.dart',
  'app/lib/ui/task_details_page.dart',
  'app/test/models_test.dart',
  'app/test/controller_test.dart','app/test/pve_api_test.dart',
  'app/test/widget_test.dart','app/test/pve_tls_test.dart',
  'app/test/incident_center_test.dart','app/test/alert_rules_test.dart',
  'app/test/alert_rules_widget_test.dart',
  'app/test/ui_components_test.dart',
  'app/test/guest_list_filter_test.dart','app/test/task_history_filter_test.dart',
  'app/test/saved_guest_view_test.dart',
  'app/test/app_preferences_test.dart','app/test/offline_overview_test.dart',
  'scripts/bootstrap_android.sh','scripts/harden_android.py',
  'scripts/check_android_generated.py',
  'scripts/android/branding/virthelm_icon.svg',
  'scripts/android/launcher/drawable/virthelm_icon_background.xml',
  'scripts/android/launcher/drawable/virthelm_icon_foreground.xml',
  'scripts/android/launcher/mipmap-anydpi-v26/ic_launcher.xml',
  'scripts/android/launcher/mipmap-anydpi-v26/ic_launcher_round.xml',
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
   'docs/64-implementation-alert-incident-inbox.md',
   'docs/65-implementation-foreground-threshold-alert-rules.md',
   'docs/66-implementation-alert-duration-hysteresis.md',
   'docs/67-ui-overhaul-foundation.md',
   'docs/68-screen-polish-followup.md',
   'docs/69-guest-detail-tabs-actions.md',
   'docs/70-node-storage-detail-tabs.md',
   'docs/71-guest-filter-sheet.md',
   'docs/72-task-summary-compact-rows.md',
   'docs/73-threshold-rule-editor.md',
   'docs/74-premerge-ui-cross-check-2026-11-07.md',
   'docs/75-connection-management-onboarding.md',
   'docs/76-accessibility-theme-completion.md',
   'docs/77-whole-repository-cross-check-2026-11-08.md',
   'docs/78-implementation-guest-recovery-readonly.md',
   'docs/79-implementation-guest-configuration-read.md']
assert all((root/p).is_file() for p in required), 'Required app source missing'
files = {p: (root/p).read_text(encoding='utf-8') for p in required}
version_match = re.search(r'^version: (\d+\.\d+\.\d+)\+', files['app/pubspec.yaml'], re.MULTILINE)
assert version_match, 'pubspec version missing'
assert f"virthelmDisplayVersion = '{version_match.group(1)}'" in files['app/lib/core/app_info.dart'], 'display version drift'
assert 'class VirtHelmStatusColors' in files['app/lib/ui/theme.dart']
assert 'class SparklineCard' in files['app/lib/ui/components.dart']
assert "Key('overview-incident-summary')" in files['app/lib/ui/shell.dart']
assert '--platforms=android' in files['scripts/bootstrap_android.sh']
assert 'android:allowBackup' in files['scripts/harden_android.py']
assert 'android:usesCleartextTraffic' in files['scripts/harden_android.py']
assert 'android.permission.INTERNET' in files['scripts/harden_android.py']
assert 'minSdk = 26' in files['scripts/harden_android.py']
assert 'debug release signing' in files['scripts/harden_android.py']
assert "launcher_resources = root / 'scripts/android/launcher'" in files['scripts/harden_android.py']
assert "('android:roundIcon', '@mipmap/ic_launcher_round')" in files['scripts/harden_android.py']
assert '#00B8AF' in files['scripts/android/branding/virthelm_icon.svg']
assert '@drawable/virthelm_icon_foreground' in files['scripts/android/launcher/mipmap-anydpi-v26/ic_launcher.xml']
assert '@drawable/virthelm_icon_background' in files['scripts/android/launcher/mipmap-anydpi-v26/ic_launcher_round.xml']
assert 'PVEAPIToken=' in files['app/lib/core/models.dart']
assert 'options.followRedirects = false' in files['app/lib/core/pve_api.dart']
assert 'SecureCredentialVault' in files['app/lib/core/profile_repository.dart']
assert 'Future<void> update(ConnectionProfile profile' in files['app/lib/core/profile_repository.dart']
assert 'Future<void> updateConnection' in files['app/lib/core/app_controller.dart']
assert 'verifyConnectionConfiguration' in files['app/lib/core/app_controller.dart']
assert 'testSavedConnection' in files['app/lib/core/app_controller.dart']
assert 'class ConnectionCheckResult' in files['app/lib/core/models.dart']
assert 'class ConnectionsPage' in files['app/lib/ui/connections_page.dart']
assert "Key('manage-connections')" in files['app/lib/ui/shell.dart']
assert 'lastServerVersion' in files['app/lib/core/models.dart']
assert 'Future<void> updateMetadata' in files['app/lib/core/profile_repository.dart']
assert "last observed" in files['app/lib/ui/connections_page.dart']
assert 'mayHaveExecuted' in files['app/lib/core/pve_api.dart']
assert 'setThemePreference' in files['app/lib/core/app_controller.dart']
assert 'AppThemePreference.amoled' in files['app/lib/main.dart']
assert 'setHighContrast' in files['app/lib/core/app_controller.dart']
assert 'setReduceMotion' in files['app/lib/core/app_controller.dart']
assert "Key('high-contrast-preference')" in files['app/lib/ui/shell.dart']
assert "Key('reduce-motion-preference')" in files['app/lib/ui/shell.dart']
assert 'View data table' in files['app/lib/ui/components.dart']
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
assert 'class GuestSnapshot' in files['app/lib/core/models.dart']
assert 'class GuestSnapshotInventory' in files['app/lib/core/models.dart']
assert 'Future<GuestSnapshotInventory> guestSnapshots' in files['app/lib/core/pve_api.dart']
assert "'${_guestPath(guest)}/snapshot'" in files['app/lib/core/pve_api.dart']
assert 'inspectGuestSnapshots' in files['app/lib/core/app_controller.dart']
assert "Key('guest-recovery-tab')" in files['app/lib/ui/guest_page.dart']
assert 'Snapshots are not backups' in files['app/lib/ui/guest_page.dart']
assert 'does not prove an archive exists' in files['app/lib/ui/guest_page.dart']
assert 'class GuestConfiguration' in files['app/lib/core/models.dart']
assert 'Future<GuestConfiguration> guestConfiguration' in files['app/lib/core/pve_api.dart']
assert "'${_guestPath(guest)}/config'" in files['app/lib/core/pve_api.dart']
assert 'inspectGuestConfiguration' in files['app/lib/core/app_controller.dart']
assert "Key('guest-configuration-tab')" in files['app/lib/ui/guest_page.dart']
assert 'only reviewed allowlisted fields' in files['app/lib/ui/guest_page.dart']
assert 'Configuration editing, create/clone, and migration remain disabled' in files['app/lib/ui/guest_page.dart']
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
assert "Key('incident-inbox-list')" in files['app/lib/ui/incident_center_tab.dart']
assert 'class ForegroundThresholdAlertRule' in files['app/lib/core/alert_rules.dart']
assert 'ForegroundThresholdAlertEngine' in files['app/lib/core/incident_center.dart']
assert 'readThresholdAlertRules' in files['app/lib/core/profile_repository.dart']
assert 'saveThresholdAlertRule' in files['app/lib/core/app_controller.dart']
assert 'class ForegroundThresholdAlertRulesPage' in files['app/lib/ui/alert_rules_page.dart']
assert 'consecutiveSamples' in files['app/lib/core/alert_rules.dart']
assert 'clearThresholdFraction' in files['app/lib/core/alert_rules.dart']
assert 'reconcileRules' in files['app/lib/core/incident_center.dart']
assert "Key('threshold-rule-consecutive-samples')" in files['app/lib/ui/alert_rules_page.dart']
assert "Key('threshold-rule-hysteresis-slider')" in files['app/lib/ui/alert_rules_page.dart']
assert "Key('manage-threshold-rules')" in files['app/lib/ui/incident_center_tab.dart']
assert '_guestTags' in files['app/lib/core/models.dart']
assert 'final List<String> tags' in files['app/lib/core/models.dart']
assert 'String? tag' in files['app/lib/core/guest_list_filter.dart']
assert 'String? pool' in files['app/lib/core/guest_saved_view.dart']
assert "Key('guest-filter-button')" in files['app/lib/ui/shell.dart']
assert "Key('guest-filter-apply')" in files['app/lib/ui/shell.dart']
assert 'guest-filter-tag-$value' in files['app/lib/ui/shell.dart']
assert 'guest-filter-pool-$value' in files['app/lib/ui/shell.dart']
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
