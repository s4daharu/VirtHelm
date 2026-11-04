# VirtHelm — merge-readiness cross-check (2026-11-04)

## Boundary of this review
Cross-checked the M1 foundation, partial M2 read cockpit, F05 guest-discovery patch, gateway, controller, local profile/vault persistence, Flutter UI, Android runner hardening, CI scripts, release prerelease workflow, and documentation. This is a source-level assessment with automated test and build evidence, **not** proof that nothing remains to be done or that no defects exist.

## Implemented versus pending
| Area | Reviewed implementation | Still missing or unverified |
|---|---|---|
| PVE profiles and TLS | HTTPS API-token onboarding, encrypted credential vault, profile switch/remove, per-origin warned insecure TLS option | Profile editing, certificate enrollment, device TLS/Keystore/restore matrix |
| Inventory and read cockpit | Nodes, QEMU/LXC guests, storage, recent tasks, freshness, 403/partial warnings | Live PVE 9.2/8.4 endpoint and ACL fixtures, persistent offline cache, RRD graphs |
| Guest discovery | Search, favorites, status/kind/node filtering, deterministic name/VMID/CPU/memory sorting | Saved views, tag/group filters, 200-guest/device accessibility and performance |
| Power operations | Target/profile validation, fresh inventory preflight, exactly one POST, UPID status, ambiguous-outcome lockout | Real PVE mutation/fault-injection matrix, persisted operation journal across process death |
| Android delivery | Flutter/Dart toolchain pinned, dependency lockfile, hardened generated runner, debug APK CI, manual signed ARM prerelease recipe | Physical install/update/signed prerelease verification, SBOM, independent security/license/dependency review |
| Premium roadmap | Product/UX/API/security plans | Console/ticket/MFA, snapshots/backups, PBS/PDM, alerts, biometrics, HA/Ceph/SDN changes and migration/provisioning are deferred |

## Corrections in this cross-check
1. **Terminal-task inventory race:** if an inventory GET was already in flight before the task completed, a plain single-flight `refresh()` could reuse that earlier read. The controller now completes any prior refresh before starting a new post-terminal inventory request, with a connection generation check.
2. **Malformed supplemental records:** storage and recent-task list parsing now counts non-string map-key rows as malformed without discarding otherwise valid items.
3. **F05 guest discovery:** filtering and sorting operate only on the already fetched active-profile snapshot, keeping write safety and cross-profile isolation intact.
4. Regression tests cover the task/refresh race and malformed map keys, as well as filtering and sort behavior. Check GitHub Actions for the actual outcome on the final branch SHA.

## Remaining release gates — explicit nonclaims
- No PVE 9.2/8.4 disposable lab tests, least-privilege ACL matrix, or live QEMU/LXC mutation fault injection were performed in this review.
- No physical Android API 26+ TLS, key-storage restore/backup, VPN transition, process death, TalkBack/font-scale, or 200-guest performance test was performed.
- No production signed build/install/update, independent penetration test, comprehensive historical secret scan, or dependency/advisory/license/SBOM review was performed.
- Task and unknown-outcome tracking are session-memory only; after process death or reconnection, operators must inspect Proxmox task history and guest state before retrying a write.
- The explicitly enabled per-profile certificate bypass is insecure even on a LAN and does not authenticate the server.

Do not promote this preview as fully certified or as the complete premium roadmap. The authoritative shipping checklist remains [Definition of Done](19-definition-of-done.md) and [release gates](33-test-acceptance-release-gates.md), with earlier evidence in [cross-check audit](41-cross-check-audit.md).
