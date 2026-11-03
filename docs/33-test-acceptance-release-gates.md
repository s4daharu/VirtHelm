# Premium Quality Engineering, Verification and Release Gates
**Truthful baseline:** current repository is documentation/CI scaffolding. No Flutter app, APK, lab-tested endpoints, pen test or production support SLA exists as of 2026-11-04.

## Test layers
| Layer | Scope | Release evidence |
|---|---|---|
| Static | formatting, analyzer, secret/license/SBOM scan, hardcoded bypass detection | CI artifact + reviewer |
| Unit | DTOs, timezones, units, permissions, actions, retry, prediction bands | named test suite |
| Contract | sanitized PVE 8.4/9.2, PBS 4.2, PDM 1.1 schema/fixtures | locked versions + captured response hashes |
| Widget/golden | loading, failure, stale, denied, R3 confirmation, a11y, themes | screenshot snapshots |
| Integration | disposable real servers: success/401/403/5xx/TLS/write error | build+test logs with redactions |
| Device | Android API 26+ phones, biometrics, notifications, restore, VPN, WebView | device roster and run ID |
| Security | OWASP MASVS controls, TLS MITM, token/cookie isolation, redaction, root limitations | signed independent review |
| Resilience | process death, stale cache, network switching, multiple cluster identities, mass guest fixtures | measured SLI |
| Disaster recovery | disposable backup verify and restore, partial failure, recovery | operator checklist |
| Release | signed artifact, reproducible SDK/toolchain, Google Play policy review, rollback plan | release manifest |

## Acceptance scenarios
**AC-01** Connection refuses invalid TLS/hostname and will not suggest bypass; cert-change blocks writes. **AC-02** Token and ticket scoped by profile; switching under 500ms race cannot act on previous site. **AC-03** Correct QEMU/LXC guest identity, VMID, unit conversions and source timestamps. **AC-04** HTTP success with UPID never prematurely shown as task success. **AC-05** Unknown write (timeout/process death) is never auto-retried; user is directed to confirm server-side state. **AC-06** Power action when guest changed node/status triggers revalidation and explicit confirmation. **AC-07** Bulk preflight gives per-guest results and cannot submit unauthorized/unknown targets. **AC-08** Snapshot rollback/delete and backup restore require named target and data-loss warning; no false recoverability claims. **AC-09** Console only through tested ticket/MFA, WebSocket secure origin and reauthentication; token-only mode unavailable. **AC-10** Alert resolved requires valid fresh data, not failed poll. **AC-11** Android background check clearly describes inexact intervals and power constraints. **AC-12** No secret on disk backups, screenshots, log output, redirect URLs, exports or lock-screen alerts. **AC-13** R3/R4 controls behave safely when cluster is not quorate. **AC-14** PVE/PBS/PDM same identifier never mixes origin. **AC-15** 200 guest fixtures remain responsive on agreed midrange Android phone.

## Server lab matrix
PVE 8.4.x and 9.2.x precisely recorded; each single node and multi-node three-node cluster; QEMU (Windows and Linux sample), LXC, HA enabled/disabled, storage local/shared/PBS-backed, Ceph optional sandbox, SDN optional sandbox; roles admin, audit-only, power-only, denied, expired, separated-token and MFA ticket. For version-sensitive 9.2 features specifically test load balancing, HA arm/disarm, custom CPU models and WireGuard/BGP SDN **only on disposable lab**. PBS 4.2/PDM 1.1 separate contract+ACL suites.

## Performance proposed SLOs
- No UI thread jank >100ms p95 in 200-guest test on representative phone (benchmark, then set realistic thresholds).
- 60fps normal scroll target with semantic accessibility modes.
- API polling default capped and paused on invisibility; no unbounded retries.
- Memory/energy and bandwidth measured in profile runs; thresholds decided after baseline.
- Crash-free beta session target >=99.5% **aspirational**, zero R3/R4 unreviewed mutations.
- Auth trust failure and command uncertainty visible within one UI frame after detection.

## Severity and release blocking
P0 Blocker: credential leakage, TLS bypass, wrong-cluster write, accidental delete/restore, impossible-to-recover HA/SDN change, misleading task completion, unknown write auto-retry. P1 Blocker for advertised capability: missing ACL/permission tests, incorrect units/stale states, console broken with supported MFA, localization/accessibility of dangerous action. Lower-priority visual quirks can enter documented bug queue.

## Evidence register entry
```yaml
feature_id: GUEST-POWER
source_api: PVE 9.2.x local API viewer + official link
server_build: exact-build
auth_mode: token-separated
acl_scope: sanitized
device: Android API 35 physical phone
test_ids: [AC-04, AC-05, AC-06]
fixture_sha256: actual-sha
app_commit: actual-sha
result: PASS | FAIL | INCONCLUSIVE
reviewed_at: YYYY-MM-DD
```
Never fill an evidence field with a guessed hash or fabricate “PASS”.
