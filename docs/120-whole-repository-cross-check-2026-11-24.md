# Whole-repository cross-check — 2026-11-24

**Baseline:** `3bb5f6390d8028295fafab0cf598d0c319813760` on `main` (0.1.75).
**Follow-up:** 0.1.76 fixes four gaps in the shipped scope without changing the
PVE API contract or Flutter dependency graph.

## Plan versus implementation

This cross-check used the [functional scope](02-feature-scope.md), [premium
milestones](32-delivery-epics-sequencing.md), [release gates](33-test-acceptance-release-gates.md),
`PROJECT_STATUS.json`, and the [previous source audit](93-whole-repository-cross-check-2026-11-11.md).
It traced the implemented slices through the controller/gateway, local storage,
Android worker, detail routes, and delivery workflows. The 200-entry catalogue
is a proposal, not a checklist of features already shipped.

| Area | Shipped boundary | Still open |
|---|---|---|
| F01–F02: profiles and auth | Saved HTTPS API-token profiles, secure credentials, connection verification, editable metadata, last-observed server version, explicit per-origin certificate exception | Dual-version restricted-token ACL fixtures, physical TLS/Keystore and backup tests; F13 ticket/MFA and broader capability negotiation are deferred |
| F03–F06, F10, F16, F18: read cockpit | Guest/node inventory and metrics, local filters and saved views, storage/task overviews, allowlisted config, effective-ACL hints, on-demand RRD and bounded capacity review/comparison | Representative-device accessibility/performance, fuller topology, statistical forecasts, broader aggregation and ACL/backend verification |
| F07–F09, F17: guest controls and tasks | One-shot QEMU/LXC power actions, exact-identity preflight, per-guest reservation through UPID and post-terminal refresh, bounded task history/status/logs | Disposable PVE 8.4/9.2 mutation/fault fixtures. Uncertain writes are not auto-retried; independent server-side verification is still required across a reconnect or process restart |
| F11–F12: preferences, network and offline | Local preferences, foreground-only refresh, gated transient GET retries, Android default-network observer, opt-in counts and 24-hour stale identity/status cache | Full offline guest/node detail cache; physical Android LAN/VPN and process-death tests |
| F14–F15: recovery | Snapshot inventory/create/delete and stopped-only non-RAM rollback; one-off backup start, archive visibility, evidence-limited confidence, GET-only alternate-VMID same-node restore planning | Backup policy/retention, integrity/PBS verification, tested restores, restore execution and advanced snapshot variants |
| F19–F22: console and operations | Bounded same-node clone, empty QEMU, unprivileged LXC, same-cluster migration and stopped-guest deletion only | Console/SPICE, broader provisioning/migration, HA/Ceph/SDN/firewall/host writes and their independent review gates |
| F23: alerts and Android | Foreground thresholds and incident triage/history; opt-in WorkManager node/task/threshold slices; bounded correlation, generic privacy-aware notifications and exact-current in-app focus; notification-only maintenance silence | Physical Android onboarding/permission/Doze/reboot/OEM/reconfiguration tests, richer correlation and maintenance, relay/critical paging, widgets/biometrics, PBS/PDM |
| Delivery and promotion | Pinned Flutter/Java, locked dependencies, generated hardened Android runner, compile-only CI, signed prereleases distributed as Release assets | Independent security/dependency/license/SBOM review and verified production signing, physical-device and repository review controls |

The earlier PVE 9.2.26 GET-only smoke evidence still applies only to its
documented scope. No new live PVE, mutation, physical device, or production
certification evidence was obtained in this pass.

## Findings corrected

1. **Obsolete scheduled checks could publish after disable or reconfiguration.**
   WorkManager cancellation does not fence a running HTTPS call. The worker now
   captures the current encrypted configuration, checks it before each GET,
   and atomically verifies it again before committing results or publishing
   a notification. Configuration/rule updates and removal share that monitor.
   An already-started request may finish; obsolete results cannot recreate
   cleared state. No token format, new PVE endpoint or permission was added.
2. **Node history comparisons could survive inventory replacement.** A peer
   request and its rendered result now require the same inventory snapshot
   as the request, like guest comparison. A refresh discards both late and
   previously displayed comparisons, even if the same nodes are still online.
   No refresh implicitly fetches peer history.
3. **The signed split verifier didn't reliably enforce negative ABI checks.**
   A negated shell pipeline does not trigger `errexit`. The workflow now
   requires the ZIP's exact expected `lib/` ABI and both required Flutter
   libraries before checksums or publication. Offline tests execute the real
   step using synthetic signatures and ZIPs that contain valid and invalid
   library layouts.
4. **The Gradle cache included task outputs.** The basic provider ignored
   configurable include paths and cached the entire `caches` directory. Both
   workflows now use the same explicit modules/wrapper cache paths and key.
   Only the Android CI workflow saves it; the signing workflow restores only.

## Verification

- Exact 0.1.75 baseline: [repository checks](https://github.com/s4daharu/VirtHelm/actions/runs/45406986511),
  [Android CI](https://github.com/s4daharu/VirtHelm/actions/runs/45406986657)
  and [signed prerelease](https://github.com/s4daharu/VirtHelm/actions/runs/45407605109)
  passed. The published ARM64 and ARMv7 assets matched their published
  checksums and contained the expected native libraries for their ABI. This
  baseline evidence does not cover the 0.1.76 changes.
- 0.1.76 local: Flutter 3.44.4 / Dart 3.12.2, unchanged dependency lock,
  formatting, analyzer, 503 Flutter tests, 24 Python tests, documentation,
  premium/source checks, workflow lint and generated-runner guards.
- The worker's new race guards were verified at source level; actual
  WorkManager edit/disable races still need device verification. Exact-SHA
  runs verify GitHub caching and build/prerelease delivery for the update.
