#!/usr/bin/env python3
"""Fail closed if Android's main manifest cannot be hardened."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
manifest = root / 'app/android/app/src/main/AndroidManifest.xml'
if not manifest.exists():
    raise SystemExit('Android runner missing: run Flutter create first.')
text = manifest.read_text(encoding='utf-8')
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
print('Hardened Android manifest: no backups, no cleartext, app label VirtHelm')
