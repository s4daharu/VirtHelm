# ALERT-002/003 foreground threshold alert rules implementation

Status: source-level M2 alerting increment with local model/repository/widget coverage. It is **not** background monitoring, Android notification delivery, a paging SLA, live PVE 8.4/9.2 validation, or production release certification.

## Implemented scope
VirtHelm now supports up to 32 profile-scoped foreground threshold rules:
- exact node CPU usage from the current cluster inventory;
- exact QEMU/LXC guest CPU usage from the current cluster inventory;
- exact per-node storage usage from the current storage overview.

Rules store only non-secret local metadata in SharedPreferences: stable rule ID, exact resource selector, display label, percentage threshold, severity and enabled state. Connection credentials remain in Android secure storage and are not rewritten when rules change.

Rules are managed from **Incidents → Manage threshold rules**. A firing threshold is merged into the existing incident inbox and can drill into the matching node, guest or storage detail route while that target is still present in the active connection generation.

## Foreground and conservative semantics
Thresholds are evaluated only after live foreground refresh work. There is no WorkManager job, background polling, notification channel, relay registration or webhook.

A rule fires when a usable current percentage is at or above its configured threshold. A clean usable sample below the threshold resolves the in-memory firing. Missing node/guest samples do not resolve an already-firing incident. Storage rules are not re-evaluated as healthy when the storage overview is partial or failed; an already-firing storage incident stays unresolved until a usable current sample is available. This preserves the monitoring rule that **unknown is not healthy**.

Rule incidents are session-local. Reconnecting or switching profiles clears the runtime firing state and re-evaluates from the next foreground live snapshot. There is still no persisted incident history.

## Deliberately deferred
ALERT-006 duration and hysteresis are implemented separately in [66-implementation-alert-duration-hysteresis.md](66-implementation-alert-duration-hysteresis.md). Later milestones implement foreground notification policy, Android scheduled checks/privacy, and a bounded scheduled node-CPU threshold slice in [105-implementation-scheduled-node-cpu-thresholds.md](105-implementation-scheduled-node-cpu-thresholds.md). Scheduled guest-CPU parity is implemented separately in [106-implementation-scheduled-guest-cpu-thresholds.md](106-implementation-scheduled-guest-cpu-thresholds.md). Scheduled storage-usage parity, certificate or backup reminders, authoritative correlation, and relay/webhook integrations remain gated.

## Verification boundary
Synthetic coverage validates rule JSON/target validation, node/guest/storage firing, conservative retention across missing samples, healthy resolution, profile isolation/purge and the rule-management UI path. Repository CI remains the formatter/analyzer/test/debug-APK gate.

The feature landed at `0.1.12+1`; CI follow-ups for pinned formatting and compact incident-header layout bring the app version to `0.1.15+1`. Real PVE 9.2/8.4 field/ACL behavior, physical Android accessibility/lifecycle/network testing, 200-guest/storage performance and release-security gates remain open.
