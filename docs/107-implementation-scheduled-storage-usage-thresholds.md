# Implementation — scheduled storage-usage thresholds

## Milestone

VirtHelm 0.1.62 adds a separate, **default-off**, best-effort Android WorkManager
option for existing foreground storage-usage threshold rules. This does not
provide continuous monitoring or certified critical paging.

## Bounded operation

- Only opted-in **enabled** storage rules are evaluated. Node/guest/storage
  threshold categories together allow at most **32** enabled worker rules.
- After a fresh authenticated node snapshot, the worker makes one read-only
  `GET /api2/json/nodes/{node}/storage` per selected visible node, with at
  most **16 distinct target nodes**. No storage GET occurs with no rules.
- Samples match the exact node and storage ID, not display labels. Only
  finite integral nonnegative used/total bytes with positive total and
  used <= total yield a usable ratio.
- Missing/duplicate/malformed target data, forbidden reads and redirects
  are incomplete evidence. They reset pending confirmation without falsely
  clearing existing active incidents or advancing whole-run last-complete time.
- Usable samples honor the existing **1–10** consecutive-sample confirmation
  and **0–20** percentage-point clear hysteresis. Rule synchronization is
  atomic across all three categories, with fail-closed worker disable on error.

## Safety and privacy

All worker requests use platform certificate and hostname validation, disable
redirects, use 10-second connect/read timeouts and a 512 KiB successful
response cap, and never submit POST/PUT/PATCH/DELETE or request an immediate
WorkManager retry. Insecure-TLS connection profiles cannot schedule checks.

Storage selectors, thresholds and authorization are only in the existing
AES-256-GCM Android-Keystore-encrypted worker secret. Native runtime state
stores only SHA-256-derived rule IDs and pending/active flags, not storage
names, nodes, byte counts, task UPIDs, logs or credentials. Foreground and
scheduled delivery retain their generic text, lock-screen policy, shared
cross-mode cooldown ledger and identifier-free notification navigation.

## Verification limits

Flutter bridge tests cover default-off policy decoding, enabled rule
filtering, atomic node/storage sync, and generic status decoding. Repository
source and Android generated-runner assertions cover endpoint, privacy,
size, cleanup and combined-rule caps. The implementation PR source `ea59e3acb53f09d3f162e4ca9a664abbad9c5e89`
passed [Docs and Android checks run 43384520765](https://github.com/s4daharu/VirtHelm/actions/runs/43384520765),
including formatting, analyzer, runtime tests, hardening checks and APK build.
The subsequent verification-record-only commit requires its own CI. Physical Android OEM/WorkManager/Keystore
checks and real PVE 8.4/9.2 backend, restricted-ACL and malformed-data
fixtures are still open release gates.

## Deferred

Cross-mode authoritative incident correlation, long-window rule semantics,
resource-specific notification links, relay/webhook delivery and production
critical-alert guarantees remain deferred.


## Follow-up

The bounded exact foreground/scheduled incident-correlation gap named above is
implemented by VirtHelm 0.1.63; see
[the cross-mode correlation milestone](108-implementation-cross-mode-incident-correlation.md).
Richer causal/cross-resource correlation remains gated.
