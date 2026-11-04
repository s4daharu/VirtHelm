#!/usr/bin/env python3
"""Offline source structure/security assertions; not a replacement for Flutter tests."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
required = [
  'app/pubspec.yaml','app/pubspec.lock','app/lib/main.dart','app/lib/core/models.dart',
  'app/lib/core/profile_repository.dart','app/lib/core/pve_api.dart',
  'app/lib/core/app_controller.dart','app/lib/core/guest_list_filter.dart',
  'app/lib/core/guest_saved_view.dart','app/lib/ui/theme.dart',
  'app/lib/ui/connect_page.dart','app/lib/ui/shell.dart',
  'app/lib/ui/guest_page.dart','app/test/models_test.dart',
  'app/test/controller_test.dart','app/test/pve_api_test.dart',
  'app/test/widget_test.dart','app/test/pve_tls_test.dart',
  'app/test/guest_list_filter_test.dart','app/test/saved_guest_view_test.dart',
  'app/lib/ui/tls_warning.dart',
  'scripts/bootstrap_android.sh','scripts/harden_android.py',
  'scripts/check_android_generated.py',
  'docs/37-implementation-m1.md','docs/38-implementation-m2-read-cockpit.md',
  'docs/39-implementation-audit.md','docs/40-profile-tls-option.md',
  'docs/41-cross-check-audit.md','docs/42-merge-readiness-cross-check.md',
  'docs/44-implementation-m2-saved-guest-views.md',
  'docs/45-full-implementation-cross-check.md',
  'docs/46-implementation-p0-profile-editing.md',
  'docs/47-implementation-p0-server-version.md']
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
assert 'storageOverview' in files['app/lib/core/pve_api.dart']
assert 'recentTasks' in files['app/lib/core/pve_api.dart']
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
assert 'TlsWarning' in files['app/lib/ui/shell.dart']
assert 'TlsWarning' in files['app/lib/ui/guest_page.dart']
print('App source smoke checks passed (not a Dart compile or device test).')
