# VirtHelm implementation milestone M2 — read cockpit slice

Status: implemented read-only slice with automated model/controller/gateway tests; this is **not** a claim of full premium M2 completion, live PVE 8.4/9.2 validation, or production readiness.

## Scope
This slice adds no new mutation endpoint:
- storage overview via per-node `GET /nodes/{node}/storage`;
- recent task history via per-node `GET /nodes/{node}/tasks?limit=20&source=all`;
- storage node/ID/backend/content/capacity/state display;
- server-task history separated from session-local mutation tracking;
- partial 403/read/malformed-record reporting without discarding successful node reads;
- profile-scoped guest favorites stored only in local application preferences;
- guest list filtering for favorites, running/stopped, QEMU/LXC, selected node, exact tag and exact pool; selectable favorites-first, name, numeric VMID, CPU and memory ordering;
- up to 12 profile-scoped named saved guest views persisted locally, with same-name updates and deletion.
- explicit on-demand guest CPU/memory RRD averages for 1 hour, 24 hours and 7 days, with text alternatives and no persistence or background polling;\n- optional guest tag/pool discovery from the existing cluster inventory, including search, exact filters, saved-view criteria and detail display.

For the node task-list endpoint, active rows are normalized from raw `status=RUNNING`; archived rows use the raw terminal task result (for example `OK`) as the exit status. That differs from `/nodes/{node}/tasks/{upid}/status`, where tracked mutations use the detail endpoint's running/stopped state plus `exitstatus`. VirtHelm does not treat an HTTP acceptance or a merely terminal task as success.

## Safety and privacy
Reads remain origin-bound to the active profile with TLS validation enabled by default and redirects disabled. The [explicit per-profile insecure exception](40-profile-tls-option.md) applies to all requests for an opted-in connection. Profile activation clears read-cockpit state. A supplemental 401 invalidates cached write authorization. Malformed guest inventory may still be displayed selectively, but guest writes are disabled until a clean inventory refresh. Task history never authorizes a mutation.

UPIDs may contain a PVE user identifier and are displayed only as local operator references. No task log body is fetched or exported by this slice.

## Guest discovery semantics
Search ignores case and surrounding whitespace and matches guest name, VMID, node, tag and pool. Kind, status, node, tag and pool filters can be combined locally without additional PVE requests. Tag filter identity preserves server-provided case; optional malformed tag/pool metadata is ignored rather than changing guest identity or write safety. The default ordering puts the active profile's favorites first, then compares names case-insensitively with deterministic VMID/kind/node tie-breaks. Explicit VMID sorting is numeric; CPU and memory descending use the current inventory snapshot, with absent, non-finite and negative values last. Filters are cleared when switching profiles, and no saved view is implied. All sorting is presentation-only; guest actions retain their existing identity/preflight safety checks.

## Bounded behavior
Recent tasks are capped at 20 per visible node and 60 combined rows. Storage is shown per node and never summed across nodes, avoiding false totals for shared storage. Guest task verification is foreground-only, single-flight, bounded by a verification TTL, and becomes `unknown` rather than retrying a mutation.

## Deliberately not implemented in this slice
Full premium M2 remains broader: node/storage and richer RRD charts, notification center/alerts, richer grouping/topology views, persistent offline cache, accessibility/performance signoff, and 200-guest/device evidence are still pending. PBS/PDM, console, ticket/MFA, snapshot/backup execution and infrastructure mutation remain later gated milestones.

## Reconciliation and malformed-read fixes
An already-in-flight inventory refresh may have started before a UPID reached terminal state. To avoid treating that old read as post-task evidence, terminal-task processing waits for it, then performs another inventory request before removing the pending guest lock. Malformed storage/task rows with non-string map keys are counted without discarding valid neighboring records. Both are covered by regression tests.

## Remaining verification
Release support still requires sanitized PVE 8.4/9.2 endpoint/ACL fixtures, single/multi-node testing, QEMU/LXC mutation fault injection, Android physical-device TLS/backup/accessibility/performance tests, dependency/security review and signed release engineering.
