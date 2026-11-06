#!/usr/bin/env python3
"""Offline documentation consistency smoke-check; no external requests."""
from pathlib import Path
import csv
import json
import re
root=Path(__file__).resolve().parents[1]
required=['README.md','SECURITY.md','CONTRIBUTING.md',
          *[f'docs/{i:02d}-{s}.md' for i,s in [
           (1,'product-requirements'),(2,'feature-scope'),(3,'ux-navigation'),
           (4,'architecture'),(5,'pve-api-contracts'),(6,'data-models'),
           (7,'security-auth'),(8,'console-rfc'),(9,'error-offline'),
           (10,'test-strategy'),(11,'roadmap-backlog'),(12,'delivery-ci'),
           (13,'compatibility-risks'),(14,'research-sources'),
           (15,'verification-matrix'),(16,'decisions'),(17,'privacy-legal'),
           (18,'setup-handbook'),(19,'definition-of-done'),(20,'publication-status')]],
          'docs/api-endpoint-index.csv','examples/README.md',
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
missing=[p for p in required if not (root/p).is_file()]
assert not missing, f'Missing required docs: {missing}'
with (root/'docs/api-endpoint-index.csv').open(newline='',encoding='utf-8') as f:
    rows=list(csv.DictReader(f))
assert len(rows)>=20, 'Expected major PVE endpoint inventory'
assert all(x['verification'] not in ('verified','tested','PASS') for x in rows), 'No fake live-validation claims'
for rel in required:
    if not rel.endswith('.md'): continue
    text=(root/rel).read_text(encoding='utf-8')
    assert text.startswith('# '), f'No H1: {rel}'
    for dest in re.findall(r'\]\(([^)#]+)(?:#[^)]*)?\)', text):
        if dest.startswith(('https://','http://','mailto:','/')): continue
        target=(root/rel).parent/dest
        assert target.exists(), f'Broken local link in {rel}: {dest}'
status=json.loads((root/'PROJECT_STATUS.json').read_text(encoding='utf-8'))
test_count=sum(
    len(re.findall(r'\btest(?:Widgets)?\s*\(', path.read_text(encoding='utf-8')))
    for path in (root/'app/test').glob('*.dart')
)
assert status['implementation_audit']['current_flutter_tests_defined'] == test_count, 'PROJECT_STATUS Flutter test count drift'
assert status['live_pve_tested'] is False, 'Repository CI must not claim live PVE validation'
print(f'Documentation smoke-check passed: {len(required)} required files, {len(rows)} endpoint rows.')
