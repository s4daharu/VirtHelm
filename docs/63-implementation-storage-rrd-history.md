# Storage RRD capacity history implementation

Status: source-level E03-01/M2 read-only increment with synthetic model/gateway/controller/widget coverage. It is **not** live PVE 8.4/9.2 compatibility evidence, physical Android certification, or production release approval.

## Scope

Storage cards on Home now open a profile- and connection-generation-scoped detail route. The route shows the current per-node storage identity, backend/content metadata and capacity snapshot, then offers explicit 1-hour, 24-hour and 7-day history loads.

History uses GET `/nodes/{node}/storage/{storage}/rrddata` with `cf=AVERAGE`. The contract basis is the official Proxmox VE API viewer referenced in [the API contract catalog](05-pve-api-contracts.md) plus upstream PVE storage RRD source behavior. The implementation retains timestamped non-negative `used` bytes and positive `total` bytes. It computes a percentage only when both are present and used does not exceed total.

## Safety and lifecycle

No mutation endpoint, Android permission, background poll, persistence, notification, cache or dependency is added.

Before and after I/O, the controller requires the same active profile ID, connection generation and exactly one currently visible storage with the same node and storage ID. Explicit Android default-network loss blocks a new history read. A profile switch or reconnect redacts the route and discards transient history. An observed HTTP 401 follows the existing authenticated-read fail-closed path, making current inventory write-unsafe until a clean authenticated refresh.

GET retries remain bounded by the existing gateway policy. There is no POST path in this feature.

## Bounded parsing and presentation

At most 1,500 response rows are considered locally. Malformed neighboring rows are counted and ignored rather than discarding valid samples. Rows are sorted by timestamp before display.

The capacity card shows latest usage, latest used/total bytes, usage range, used-byte range and sample count as text in addition to the sparkline. Timeframe selection alone never performs a request; the user must choose **Load history** or **Refresh history**. Samples remain widget-local and disappear when the route is discarded.

Shared storage continues to be represented per node. VirtHelm does not sum storage totals across nodes and does not infer cluster-wide capacity from repeated shared-storage records.

## Verification added

Synthetic regressions cover:

- conservative storage RRD point parsing and invalid-ratio handling;
- exact GET path, `timeframe`, `cf=AVERAGE`, sorting and malformed-row accounting;
- profile/generation/exact-storage controller isolation with no mutation submission;
- Android-network short-circuit and 401 write-safety invalidation;
- explicit-load UI behavior, timeframe reset, accessible text summaries and session redaction.

The app version is bumped to `0.1.10+1`. Repository CI remains the compile/analyzer/debug-build gate for the pushed commit.

## Remaining evidence

Release support still requires sanitized PVE 9.2 and 8.4 storage RRD fixtures across representative local/shared/backed storage types, ACL/403 behavior, units, missing-series semantics, timestamp resolution and cluster forwarding. Physical Android TalkBack/font-scale/performance/network/TLS testing, dependency/security review and production release approval also remain open.

This increment does not mark premium catalog items complete. Cross-resource capacity comparison, runway/anomaly estimates, alerts, 30-day analytics, persistent offline details and infrastructure storage mutations remain deferred.
