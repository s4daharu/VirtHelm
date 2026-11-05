# Guest detail follow-up — cumulative network and disk I/O counters

**Increment:** 2026-11-05. Read-only Android source implementation stacked after [F09 task-history filters](56-implementation-f09-task-history-filters.md). This does **not** establish live PVE 9.2/8.4 or physical Android release compatibility.

## Scope and metric semantics

- The existing `GET /cluster/resources` guest resource records may include `netin`, `netout`, `diskread`, and `diskwrite` for QEMU/LXC resources. Guest detail now displays optional **Received**, **Sent**, **Read**, and **Written** totals under a distinct **Guest I/O counters** section.
- These values are **cumulative byte counters**, not instantaneous or averaged network/disk rates. Proxmox may reset counters when a guest restarts. The UI explicitly labels totals as reported since guest start, so operators do not misinterpret a large cumulative value as a current throughput spike.
- Only nonnegative integer values (including integral JSON doubles) are accepted. Negative, fractional, infinite, string, missing or malformed counters are displayed as **unavailable** (`—`), not silently treated as zero. An explicit zero remains `0 B`.
- Existing `formatBytes` unit formatting is reused. Current inventory timestamps and stale/offline warnings already on the guest page continue to govern freshness; no new background sampler, statistics persistence, or charts are added.

## Security and lifecycle

- No new API endpoints, authentication scopes, network requests, mutation paths, token storage, copy/export controls or telemetry were introduced. All four fields come from the existing read-only inventory request.
- Guest detail continues to resolve the currently active profile and exact node/type/VMID from the current in-memory inventory. When the displayed profile changes, fields from the previous profile are replaced by unavailable values rather than reusing stale guest counter samples.
- Guest power confirmations, fresh preflight, single-flight POST, ambiguous-outcome lockout, UPID verification and terminal inventory reconciliation remain unchanged.

## Cross-check correction — guest-route session isolation\n\nAn application-wide audit discovered that an already-open guest-detail route could still show the previous guest name, node and VMID after switching connection profiles, and a same-profile reconnect was not distinguished from the original session. The guest page now captures its connection generation when navigation begins and renders a neutral **Guest unavailable** state on any profile-ID or generation mismatch, without displaying the previous guest identity or counters. A pending power confirmation also switches to an identity-free, non-confirmable dialog on session change; the post-dialog handler checks the generation again before requesting any action. Synthetic widget coverage explicitly switches profiles and reconnects the same profile with the dialog open. This is a targeted source-level privacy/write UX fix; device and process-death validation remain open.\n\n## Verification

Synthetic model tests cover positive and zero counters, optional fields, malformed/negative/fractional/string/infinite values, and byte formatting. A widget test checks on-screen labels, totals, unavailable values and redaction after a profile switch. Exact-head PR CI must pass docs/Python guards, pinned Dart formatting, `flutter analyze --fatal-infos`, Flutter tests and debug APK build.

**Still open:** sanitized PVE 9.2/8.4 field/units/restart-reset fixtures across QEMU and LXC; ACL matrices; device accessibility/performance/TLS and independent security review. Do not call this release-certified.
