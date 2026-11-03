# Compatibility, Architectural Tradeoffs and Risks

## Supported versions
**Primary:** PVE 9.2, latest listed official release when checked 2026-11-04 (released 2026-05-21). **Secondary regression:** PVE 8.4 (official ISO reference). A version listed is **not** a tested version; evidence required before users are told it is supported. API viewer at the installed PVE host is the source of truth, not merely latest online documentation. Proxmox Backup Server and Proxmox Datacenter Manager are explicitly unsupported.

## Risks register
| ID | Risk / consequence | Severity | Mitigation and verification |
|---|---|---|---|
| R01 | TLS on home PVE uses self-signed cert; user may demand bypass | Critical | trustworthy CA/cert onboarding, never global bypass; negative TLS tests |
| R02 | API token not eligible for console | High | console postponed; user ticket MFA & WebSocket RFC |
| R03 | Too-broad admin token or leaked secret | Critical | least privilege, expiry, Keystore, no logs, revocation playbook |
| R04 | 403 hides resources, incorrect “cluster empty” UI | High | permission-limited integration fixtures, partial-access message |
| R05 | API schema/action parameters drift between 8.4/9.2 | High | endpoint/version matrix and test fixtures, typed parsers with unknown fields |
| R06 | Async task marked successful immediately | High | task UPID status/exitstatus tracking, no optimistic success |
| R07 | Retry after timeout double-submits write | High | reads-only auto-retry, unknown outcome and verification UI |
| R08 | Background polling drains battery/causes load | Medium | foreground-only, backoff, cancel profile/context changes |
| R09 | Single-node API proxy unavailable | Medium | offline/stale state, optional manual alternate entrypoint; no assume seamless failover |
| R10 | New package minSdk/compileSdk breaks build | High | pinned matrix, secure storage changelog, CI Android build |
| R11 | Phone UI unusable with 2x font / TalkBack | Medium | accessibility and 320dp QA |
| R12 | Proxmox branding/licensing issue | Medium | independent/unofficial naming and asset review, license audit |
| R13 | Stale cache shows wrong power state | High | timestamp, data invalidation before mutation, fresh confirmation |
| R14 | Complex tenant routing / cross-profile actions | Critical | profile ID in all domain keys, cancellation, concurrency stress test |
| R15 | Misunderstood cloud backup semantics for secrets | High | Android backup exclusion, restore tests, no cloud sync by default |

## Disputed/unknown items to settle through experiments
- Does a specific 8.4/9.2 endpoint demand form-urlencoded vs JSON? Validate actual method/input mapping.
- Exactly which ACL privilege/path is necessary per endpoint and storage? Read each API viewer permission block and run a least-privileged test.
- How does ticket login with realm-specific TFA work on installed PVE 8.4 vs 9.2? Capture non-secret flow artifacts.
- Can a user-selected internal CA be trusted through a per-profile Dart security context without affecting global trust? Threat model and Android real-device tests.
- How is `vncwebsocket` user session authenticated in Android WebView/native WS across reverse proxies? Spike, do not assume.
- Does any endpoint return sync data vs UPID under some parameter combinations? Test before stable type signature.

## Stop-ship conditions
Any unreviewed TLS bypass, secret in logs/Git, unverified destructive POST, wrong-cluster routing, failure task shown as success, unsupported console claim or absence of negative auth tests is a release blocker.
