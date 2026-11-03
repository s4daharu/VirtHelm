# Claim-to-Source and Release Verification Matrix

Evidence status codes: **DOC** = official documentation/source substantiates concept; **PLAN** = chosen implementation design; **PENDING** = live integration or security validation required; **PASS** = testing evidence attached (none at initial authoring).

| Claim / behavior | Source ID | Current evidence | Test required |
|---|---|---|---|
| Latest publicly listed release is PVE 9.2 (as of 2026-11-04) | S01/S02 | DOC | revisit release registry before shipment |
| PVE HTTPS API listens on 8006 and forwards cluster requests | S04 | DOC | probe single + multi-node lab |
| Correct header uses `PVEAPIToken=user@realm!id=secret` | S03 | DOC | T01 header unit, token integration |
| Separated API token rights intersect user/token rights | S03 | DOC | permission matrix on lab |
| API tokens do **not** access VM/system console endpoints | S03 | DOC | T02 negative console experiment |
| `/version` returns server version | S06 | PENDING | 8.4/9.2 fixtures |
| `/cluster/resources` and guest lists schema | S06/S07 | PENDING | 8.4/9.2 fixtures, partial ACL |
| QEMU/LXC lifecycle POST exact method/params | S06/S08/S09 | PENDING | 8.4/9.2 guest mutation tests |
| UPID task terminal state/exitstatus contract | S06/S07 | PENDING | normal and failure terminal tasks |
| CPU/mem/disk/uptime units for each endpoint | S06 | PENDING | fixture unit tests and manual cross-check |
| Ticket/CSRF flow for supported auth realms | S03/S06 | PENDING | login + TFA + expiry tests before P1 |
| Android TLS should use trusted CA and hostname | S13/S14 | DOC | MITM, expired cert, wrong host |
| Android secure storage package backup/migration concerns | S15/S16 | DOC | physical device restore tests |
| Android minSdk 26 is product target | S12/S16 | PLAN | compile/test devices |
| MVVM + repositories + services architecture | S10/S11 | PLAN | code review/lint |
| Force-stop confirmation and no write auto-retry | security design | PLAN | widget and fault-injection tests |
| 60fps at 200 guests and p95 launch target | PRD | PENDING | benchmark on agreed phone |

## Evidence entry template
```yaml
claim_id: QEMU-STATUS-START
pve_version: '9.2.x exact build'
api_viewer_export_hash: '<sha256>'
fixture_hash: '<sha256>'
role_acl: '<sanitized path/role>'
android_api: 35
app_commit: '<sha>'
test_ids: ['T06','T07','T08']
result: PASS | FAIL | INCONCLUSIVE
reviewed_by: '<engineer>'
reviewed_at: 'YYYY-MM-DD'
```

**Rule:** source-only confidence is not execution proof. “100% correct data” cannot be guaranteed in absence of a real PVE cluster; this matrix makes uncertain claims and missing evidence visible.
