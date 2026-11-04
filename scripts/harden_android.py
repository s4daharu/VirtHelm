#!/usr/bin/env python3
"""Fail closed if the generated Android runner cannot be hardened."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
manifest = root / 'app/android/app/src/main/AndroidManifest.xml'
gradle = root / 'app/android/app/build.gradle.kts'
if not manifest.exists() or not gradle.exists():
    raise SystemExit('Android runner missing: run Flutter create first.')

text = manifest.read_text(encoding='utf-8')
manifest_open = re.search(r'<manifest\b[^>]*>', text, re.S)
if manifest_open is None:
    raise SystemExit('Manifest root missing; refusing unsecured runner.')
if 'android.permission.INTERNET' not in text:
    permission = '\n    <uses-permission android:name="android.permission.INTERNET"/>'
    text = text[:manifest_open.end()] + permission + text[manifest_open.end():]

start = re.search(r'<application\b[^>]*>', text, re.S)
if start is None:
    raise SystemExit('Main application node missing; refusing unsecured runner.')
node = start.group(0)
for name, value in (
    ('android:allowBackup', 'false'),
    ('android:usesCleartextTraffic', 'false'),
    ('android:label', 'VirtHelm'),
):
    if re.search(fr'{name}="[^"]*"', node):
        node = re.sub(fr'{name}="[^"]*"', f'{name}="{value}"', node)
    else:
        node = node[:-1] + f' {name}="{value}">'
text = text[:start.start()] + node + text[start.end():]
manifest.write_text(text, encoding='utf-8')

gradle_text = gradle.read_text(encoding='utf-8')
min_sdk = 'minSdk = flutter.minSdkVersion'
if min_sdk not in gradle_text:
    raise SystemExit('Generated minSdk pattern changed; review Flutter template.')
gradle_text = gradle_text.replace(min_sdk, 'minSdk = 26', 1)
debug_signing = 'signingConfig = signingConfigs.getByName("debug")'
if debug_signing not in gradle_text:
    raise SystemExit('Generated release signing pattern changed; review Flutter template.')
gradle_text = gradle_text.replace(
    debug_signing,
    '// Release signing intentionally not configured in source control.',
    1,
)
gradle_text = gradle_text.replace(
    '// TODO: Add your own signing config for the release build.\n'
    + '// Signing with the debug keys for now, so `flutter run --release` works.\n',
    '// Release signing must be supplied outside Git before distribution.\n',
)
gradle.write_text(gradle_text, encoding='utf-8')
print(
    'Hardened Android runner: INTERNET enabled, backups/cleartext disabled, '
    'minSdk 26, no debug release signing'
)
