#!/usr/bin/env python3
"""Fail closed if the generated Android runner cannot be hardened."""
from pathlib import Path
import re
import shutil

root = Path(__file__).resolve().parents[1]
manifest = root / 'app/android/app/src/main/AndroidManifest.xml'
gradle = root / 'app/android/app/build.gradle.kts'
if not manifest.exists() or not gradle.exists():
    raise SystemExit('Android runner missing: run Flutter create first.')

text = manifest.read_text(encoding='utf-8')
manifest_open = re.search(r'<manifest\b[^>]*>', text, re.S)
if manifest_open is None:
    raise SystemExit('Manifest root missing; refusing unsecured runner.')
for permission in ('android.permission.INTERNET', 'android.permission.ACCESS_NETWORK_STATE',
                   'android.permission.POST_NOTIFICATIONS'):
    if permission not in text:
        declaration = f'\n    <uses-permission android:name="{permission}"/>'
        text = text[:manifest_open.end()] + declaration + text[manifest_open.end():]

start = re.search(r'<application\b[^>]*>', text, re.S)
if start is None:
    raise SystemExit('Main application node missing; refusing unsecured runner.')
node = start.group(0)
for name, value in (
    ('android:allowBackup', 'false'),
    ('android:usesCleartextTraffic', 'false'),
    ('android:label', 'VirtHelm'),
    ('android:roundIcon', '@mipmap/ic_launcher_round'),
):
    if re.search(fr'{name}="[^"]*"', node):
        node = re.sub(fr'{name}="[^"]*"', f'{name}="{value}"', node)
    else:
        node = node[:-1] + f' {name}="{value}">'
text = text[:start.start()] + node + text[start.end():]
manifest.write_text(text, encoding='utf-8')

gradle_text = gradle.read_text(encoding='utf-8')
min_sdk = 'minSdk = flutter.minSdkVersion'
if min_sdk not in gradle_text and 'minSdk = 26' not in gradle_text:
    raise SystemExit('Generated minSdk pattern changed; review Flutter template.')
gradle_text = gradle_text.replace(min_sdk, 'minSdk = 26', 1)
debug_signing = 'signingConfig = signingConfigs.getByName("debug")'
if (debug_signing not in gradle_text and
        '// Release signing intentionally not configured in source control.' not in gradle_text):
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

# The generated Android runner is ignored. Reapply our reviewed activity
# deterministically; fail closed if Flutter changes the generated class shape.
activity = root / 'app/android/app/src/main/kotlin/com/s4daharu/virthelm/MainActivity.kt'
template = root / 'scripts/android/MainActivity.kt'
if not activity.is_file() or not template.is_file():
    raise SystemExit('Generated MainActivity or native template missing.')
activity_text = activity.read_text(encoding='utf-8')
if ('package com.s4daharu.virthelm' not in activity_text or
        not re.search(r'class MainActivity\s*:\s*FlutterActivity\(\)', activity_text)):
    raise SystemExit('Generated MainActivity changed; review before replacement.')
activity.write_text(template.read_text(encoding='utf-8'), encoding='utf-8')

# Keep launcher branding outside the ignored Android runner, then install it
# deterministically after every Flutter runner generation.
launcher_resources = root / 'scripts/android/launcher'
runner_resources = root / 'app/android/app/src/main/res'
if not launcher_resources.is_dir():
    raise SystemExit('Reviewed launcher resources missing; refusing unbranded runner.')
runner_resources.mkdir(parents=True, exist_ok=True)
for source in launcher_resources.rglob('*'):
    if not source.is_file():
        continue
    destination = runner_resources / source.relative_to(launcher_resources)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)

# Flutter's template requests an 8G heap, which can thrash an 8 GB host.
# Preserve unrelated settings while enforcing the project's build resource caps.
properties = root / 'app/android/gradle.properties'
caps = {
    'org.gradle.jvmargs': '-Xmx2048m -XX:MaxMetaspaceSize=512m',
    'org.gradle.workers.max': '2',
    'org.gradle.parallel': 'false',
    'kotlin.daemon.jvmargs': '-Xmx512m',
}
lines = properties.read_text(encoding='utf-8').splitlines() if properties.exists() else []
lines = [line for line in lines if line.split('=', 1)[0].strip() not in caps]
lines.extend(f'{key}={value}' for key, value in caps.items())
properties.write_text('\n'.join(lines) + '\n', encoding='utf-8')
print(
    'Hardened Android runner: network/notification permissions enabled, backups/cleartext disabled, '
    'minSdk 26, branded adaptive launcher icon, no debug release signing, capped '
    'Gradle/Kotlin resources'
)
