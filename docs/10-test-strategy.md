# Test Strategy and Acceptance Matrix

## Confidence model
- **Documented:** an official source substantiates a statement.
- **Source inspected:** checked official source code / API viewer for endpoint family (not live operation).
- **Fixture verified:** deterministic response fixture captured on named version under authorized test account.
- **Integration passed:** endpoint exercised against real non-production PVE in representative auth modes.
- **Release validated:** integration + Android device + negative/edge tests pass.

No implementation/spec is “100% correct” without the full relevant verification evidence. Preserve version, test harness, timestamp, command and sanitized response artifacts per case.

## Levels
1. **Pure Dart unit:** URL parsing, token auth formatting, typed JSON decoding, CPU/memory/uptime formatting, status maps, task state, failure mapping, profile isolation.
2. **Service with fake adapter:** expected GET/POST, request path and header, 401/403, malformed/unknown data, timeout, UPID handling, no retries on writes.
3. **Widget tests:** login, form validation, loading/empty/error/offline, talkback semantics, safe confirmations, long names, theme/font scale.
4. **Integration test lab:** dedicated PVE 9.2 and 8.4 cluster or isolated nodes, QEMU VM and LXC, both limited and admin auth profiles; each mutation includes teardown/rollback.
5. **Android instrumented/device:** minimum API (chosen 26), contemporary versions (e.g. 33/35/37), physical phone on LAN/VPN, airplane mode, keychain/device lock, rotation, background/foreground.
6. **Security regression:** invalid/expired certificate, incorrect hostname, invalid token, restricted scope, missing CSRF for ticket mode, malicious redirect, unsafe JSON, logs and backup restore.

## Version matrix (explicit release target, not completed)
| Environment | API token view | guest actions | task polling | storage | ticket/2FA | console |
|---|---|---|---|---|---|---|
| PVE 9.2 (primary) | Must pass P0 | Must pass P0 | Must pass P0 | Must pass P0 | P1 spike | P2 RFC |
| PVE 8.4 (regression) | Must pass P0 | Must pass P0 | Must pass P0 | Must pass P0 | P1 spike | P2 RFC |
| Single-node/cluster multi-node | Must pass | Must pass | Must pass | Must pass | future | future |
| Empty and read-only user | Must pass | 403 correctly | no invented success | optional | future | unavailable |

## Critical tests (each requires documented evidence)
- T01 Correct header **including separator**: `PVEAPIToken=user@realm!id=secret`.
- T02 API token can't establish console; no UI action promises token-only console.
- T03 Accepted TLS CA + valid hostname connects; MITM, wrong hostname, expired cert fail closed by default. Test explicit insecure opt-in, cancellation, persistence, exact-origin scoping and profile isolation per [TLS option](40-profile-tls-option.md).
- T04 GET returns `data: []`, `data: null` or malformed; parser supplies correct empty/error semantics.
- T05 CPU 0.1 prints 10%, not 0.1% or 100%; `mem=0` and `maxmem=0` no division by zero.
- T06 QEMU and LXC start/shutdown/stop/reboot separately return task IDs or documented synchronous patterns.
- T07 task `status=stopped`, `exitstatus != OK` renders failure; `status=running` not success.
- T08 POST times out after server accepted: UI reports unknown; does not auto-submit again.
- T09 permission denied after an initially successful read: no stale cached action authorization.
- T10 profile A and B same vmid => no cross-cluster action, cache or credential bleed.
- T11 token revoked/expired while app backgrounded: credentials fail gracefully; no plaintext fallback.
- T12 Android backup/restore does not restore orphaned encrypted credentials or leak profiles.
- T13 200 guests and 4-node fixture: smooth lazy list, bounded request count, cancellation.
- T14 200% font scale and screen reader labels, force stop requires unambiguous confirmation.
- T15 all request/response logs and crash diagnostics scanned for real test tokens and cookies.

## Lab safety
Use a non-production cluster and disposable guests with snapshots/backups; no host reboots or arbitrary VM deletion. Do not run destructive mutations as part of CI without guarded environment/approval. Record role ACL, API viewer export or schema, PVE `pveversion -v` sanitized, Android device/build versions, request/response metadata (with redacted headers).

## Test evidence template
```text
ID: T06-QEMU-START
PVE: 9.2.x; date: YYYY-MM-DD; node: staging-1
Auth: separated-token; ACL reference (no secret)
Method/path: POST /api2/json/nodes/staging-1/qemu/101/status/start
Result: HTTP ..., data type ..., UPID stored ...
Task terminal: stopped; exitstatus: OK or descriptive error
Android: device/API level; app commit SHA
Evidence: sanitized fixture, log scrub passed, reviewer
```
