# Claim-to-Source and Release Verification Matrix

Evidence status codes: **DOC** = official source substantiates the concept; **AUTO** = implemented behavior covered by automated source/unit/contract/build checks; **PLAN** = chosen design; **PENDING** = real integration/security/device evidence still required; **PASS** is reserved for attached target-environment evidence.

| Claim / behavior | Current evidence | Remaining evidence |
|---|---|---|
| PVE HTTPS/API-token protocol and token-console limitation | DOC + AUTO header/transport tests | PVE 8.4/9.2 auth/ACL lab |
| HTTPS-only origin, redirect rejection, explicit TLS failure | AUTO | physical-device valid/wrong-name/expired/private-CA tests |
| Profile credential isolation and secure-storage metadata separation | AUTO | Android Keystore backup/restore/device-loss tests |
| Guest detail/confirmation redaction on profile switch and same-profile reconnect | AUTO widget regression and generation guards | physical Android route/dialog race and screen privacy testing |
| Cluster resource/guest parsing, units and uptime | AUTO | sanitized 8.4/9.2 fixtures and permission variants |
| Optional cumulative guest network/disk byte counters from cluster resources | AUTO synthetic parser/widget tests | PVE 8.4/9.2 counter availability/units/restart-reset fixtures and physical-device accessibility |
| On-demand guest CPU/memory RRD history with route-session isolation and text alternatives | AUTO synthetic parser/gateway/controller/widget tests | PVE 8.4/9.2 QEMU/LXC RRD payload/ACL/resolution fixtures and physical Android accessibility/performance |
| QEMU/LXC start/shutdown/reboot/stop paths and one-POST behavior | AUTO contract/fault guards | disposable 8.4/9.2 mutation tests |
| Mutation single-flight, stale/profile race rejection, unknown timeout lockout | AUTO | network fault injection against real PVE |
| Task-detail terminal success requires stopped + OK exit status | AUTO | live successful/failed task fixtures |
| Node task-list RUNNING/archive-result normalization | source-inspected + AUTO | live 8.4/9.2 task-list fixtures |
| Storage partial 403/malformed handling and no shared-total summation | AUTO | local/shared/PBS-backed PVE storage fixtures |
| Guest search/favorites/type/node filters/sorting and profile-scoped saved views | AUTO local model/repository/controller/widget coverage | 200-guest physical-device accessibility/performance evidence |
| Guest tag/pool discovery, search/filtering and saved-view compatibility | DOC upstream tag contract + AUTO local parser/filter/widget coverage | PVE 8.4/9.2 tag/pool field + ACL/case/nested-pool fixtures and physical-device accessibility/performance |
| Connection cancellation/profile-deletion local persistence cleanup | AUTO race/malformed-metadata regression coverage | Android Keystore/process-death/device-loss validation |
| Android minSdk 26, release Internet, no cleartext/backup, no debug release signing | AUTO generated-runner CI | merged release-manifest/device backup and signing tests |
| Reproducible Flutter dependency graph | AUTO committed lock + pinned Flutter 3.44.4 | deliberate dependency/security update review |
| Android default-network callback and post-loss action guard | AUTO synthetic controller/native bridge tests | physical airplane-mode, isolated-LAN, VPN and process-death tests |
| Contextual TLS exception labels without permanent banner | AUTO source/widget tests | physical Android accessibility and TLS security review |
| 200-guest responsiveness/accessibility targets | PENDING | representative phone benchmark/TalkBack/font-scale |
| Ticket/MFA, console, PBS/PDM and high-risk operations | PLAN/deferred | separate milestone RFC/integration gates |

**Rule:** automated tests and a debug APK do not establish server/device/release correctness. Never enter target-environment `PASS` without the sanitized evidence required by `docs/10-test-strategy.md` and `docs/19-definition-of-done.md`.
