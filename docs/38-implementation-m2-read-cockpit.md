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
- guest list filtering for favorites, running and stopped workloads, with favorites surfaced first.

For the node task-list endpoint, active rows are normalized from raw `status=RUNNING`; archived rows use the raw terminal task result (for example `OK`) as the exit status. That differs from `/nodes/{node}/tasks/{upid}/status`, where tracked mutations use the detail endpoint's running/stopped state plus `exitstatus`. VirtHelm does not treat an HTTP acceptance or a merely terminal task as success.

## Safety and privacy
Reads remain origin-bound to the active profile with TLS validation and redirects disabled. Profile activation clears read-cockpit state. A supplemental 401 invalidates cached write authorization. Malformed guest inventory may still be displayed selectively, but guest writes are disabled until a clean inventory refresh. Task history never authorizes a mutation.

UPIDs may contain a PVE user identifier and are displayed only as local operator references. No task log body is fetched or exported by this slice.

## Bounded behavior
Recent tasks are capped at 20 per visible node and 60 combined rows. Storage is shown per node and never summed across nodes, avoiding false totals for shared storage. Guest task verification is foreground-only, single-flight, bounded by a verification TTL, and becomes `unknown` rather than retrying a mutation.

## Deliberately not implemented in this slice
Full premium M2 remains broader: charts/RRD, named saved views, notification center/alerts, advanced filters/sorting, persistent offline cache, accessibility/performance signoff, and 200-guest/device evidence are still pending. PBS/PDM, console, ticket/MFA, snapshot/backup execution and infrastructure mutation remain later gated milestones.

## Remaining verification
Release support still requires sanitized PVE 8.4/9.2 endpoint/ACL fixtures, single/multi-node testing, QEMU/LXC mutation fault injection, Android physical-device TLS/backup/accessibility/performance tests, dependency/security review and signed release engineering.
