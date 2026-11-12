# Implementation — background failed-task checks

## Milestone

VirtHelm 0.1.58 implements a bounded failed-task parity slice for Android
scheduled monitoring. Existing WorkManager node-state checks remain enabled by
the primary scheduled-check opt-in; recent failed-task scanning is a separate
secondary opt-in on the same profile.

This is not full foreground/background alert parity. Threshold-rule evaluation,
authoritative incident correlation, resource-specific notification links,
relay delivery, an SLA and critical paging remain gated.

## Operator behavior

When scheduled checks are enabled, the Scheduled checks page exposes
**Include recent failed tasks**.

When off, the worker keeps the 0.1.53 node-state behavior.

When on, each eligible WorkManager run:

- performs the existing bounded cluster node-state GET;
- uses only the node identifiers returned by that authenticated node response;
- checks at most 16 nodes;
- requests at most 20 recent task rows per node;
- emits only the existing generic incident notification when a node-state or
  failed/unknown terminal-task category newly becomes active.

The task option is disabled by default for existing saved scheduled policies.
Quiet hours, notification cooldown, lock-screen privacy, generic Incidents
navigation and the shared 0.1.57 foreground/scheduled delivery ledger remain
unchanged.

## Read-only API boundary

The optional task scan adds GET-only reads to:

`/api2/json/nodes/{node}/tasks?limit=20&source=all`

The worker still never submits POST, PUT, PATCH or DELETE, never follows HTTP
redirects, uses 10-second connect/read timeouts, caps each successful response
at 512 KiB, uses the platform HTTPS certificate/hostname verifier and never
requests an immediate WorkManager retry.

Node names must match a conservative local path-segment allowlist before they
are used in a task URL. A cluster returning more than 32 usable nodes makes the
task side incomplete instead of starting an unbounded request waterfall.

## Task result semantics

The worker mirrors the foreground failed-server-task contract conservatively:

- `RUNNING` is not an incident;
- terminal `OK` is healthy;
- a terminal result with an explicit non-`OK` exit status is an incident;
- terminal status values such as `ERROR` reported directly in `status` are
  treated as that non-`OK` exit status, matching the Flutter parser;
- bare terminal `stopped` without an exit status remains unknown and does not
  become a failed-task incident;
- `unknown` status remains unknown and does not become a failed-task incident;
- missing/malformed task records, denied authorization, redirects and request
  failures make the task side incomplete.

An incomplete task read never clears a previously active task incident and does
not update the "last complete check" timestamp. The independently complete node
side can still transition and notify during a task-read failure, so enabling
task checks does not disable previously working node-state monitoring.

Native occurrence state stores only two per-profile booleans: node incident
active and task incident active. It does not persist UPIDs, task types, resource
IDs, node names, guest names, VMIDs, timestamps from task rows, logs or raw API
responses.

## Notification and privacy boundary

A notification is eligible only when a fully evaluated category transitions
from inactive to active. The notification remains:

- title: `VirtHelm scheduled incident`;
- body: `Open VirtHelm to review current incidents.`

The Android payload and navigation intent contain no resource selector. The
shared delivery ledger stores only a SHA-256-derived profile key and successful
delivery timestamp. ALERT-010 secure-lock-screen privacy and AND-010 generic
Incidents navigation remain authoritative.

## Verification

Repository regression coverage adds a Flutter channel contract test for the new
opt-in and source/generated-runner assertions for:

- backward-compatible default-off policy parsing;
- explicit bridge serialization;
- the 32-node bound;
- the 20-row GET-only task endpoint;
- separate native task occurrence state;
- unchanged no-POST/no-PUT/no-DELETE Android safety checks.

Source/build CI is required before this milestone is treated as exact-head
verified. Physical-device process-death/Doze/OEM behavior and live PVE 8.4/9.2
task payload, ACL and pagination behavior remain release gates.

## Remaining work

Still gated: scheduled threshold-rule parity, richer failed-task windowing and
correlation, authoritative cross-resource incident correlation,
resource-specific notification links, optional relay/webhook delivery,
production critical-alert guarantees and release certification.
