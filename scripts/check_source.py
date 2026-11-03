#!/usr/bin/env python3
"""Offline source structure/security assertions; not a replacement for Flutter tests."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
required = [
  'app/pubspec.yaml','app/lib/main.dart','app/lib/core/models.dart',
  'app/lib/core/profile_repository.dart','app/lib/core/pve_api.dart',
  'app/lib/core/app_controller.dart','app/lib/ui/theme.dart',
  'app/lib/ui/connect_page.dart','app/lib/ui/shell.dart',
  'app/lib/ui/guest_page.dart','app/test/models_test.dart',
  'app/test/controller_test.dart','app/test/widget_test.dart',
  'scripts/bootstrap_android.sh','scripts/harden_android.py',
  'docs/37-implementation-m1.md']
assert all((root/p).is_file() for p in required), 'Required app source missing'
files = {p: (root/p).read_text(encoding='utf-8') for p in required}
assert '--platforms=android' in files['scripts/bootstrap_android.sh']
assert 'android:allowBackup' in files['scripts/harden_android.py']
assert 'android:usesCleartextTraffic' in files['scripts/harden_android.py']
assert 'PVEAPIToken=' in files['app/lib/core/models.dart']
assert 'followRedirects: false' in files['app/lib/core/pve_api.dart']
assert 'SecureCredentialVault' in files['app/lib/core/profile_repository.dart']
assert 'mayHaveExecuted' in files['app/lib/core/pve_api.dart']
assert 'GuestAction.stop' in files['app/lib/core/app_controller.dart'] or 'GuestAction' in files['app/lib/core/app_controller.dart']
for p in (root/'app/lib').rglob('*.dart'):
    data = p.read_text(encoding='utf-8')
    assert 'badCertificateCallback' not in data
    assert 'SecurityContext(withTrustedRoots: false)' not in data
print('App source smoke checks passed (not a Dart compile or device test).')
