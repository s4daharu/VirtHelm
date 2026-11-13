# Implementation milestone — bounded cross-mode incident correlation (0.1.63)

Date: 2026-11-14  
Scope: EP-ALERT / M6 incident-correlation follow-up

## Milestone

VirtHelm now correlates exact incidents that are observable in the unlocked
foreground session with the most recent matching evidence produced by the
opted-in Android scheduled monitor. This closes the previous split where
foreground durable history and scheduled occurrence state could describe the
same node, failed task, or threshold rule without any local relationship.

The boundary is deliberately narrow. Scheduled evidence **cannot create a live
incident, close one, change severity, acknowledge it, authorize a drill-down or
permit a mutation**. A foreground authenticated read remains the only source of
current incident identity and health. If a resource is no longer identifiable
when VirtHelm opens, opaque scheduled evidence is not reverse-mapped into a
resource name.

## Correlation contract

The scheduled worker records five independently replaceable components:

- node-state incident identities;
- definite failed-task identities;
- active node-CPU rule identities;
- active guest-CPU rule identities;
- active storage-usage rule identities.

Each component stores only its latest observation timestamp plus SHA-256 values
derived from the already SHA-256-derived profile key, a category label, and the
exact identity. No node name, VMID, storage ID, task UPID, rule ID, endpoint,
credential, threshold, sampled value, task log or response body is written into
the correlation preference.

A complete component read replaces that component. A complete healthy component
therefore clears its older hashes. An incomplete/denied/malformed component does
not clear older evidence, matching the existing rule that **unknown is not
healthy**. Configuration/rule changes clear correlation context rather than
reattributing old hashes to changed rules.

When an unlocked foreground refresh has current incidents, Dart sends at most
128 exact current identities over the in-process method channel. Native code
hashes those candidates and returns only matching incident keys with their
scheduled observation timestamp. The raw candidates are not persisted by this
path. Task UPIDs remain excluded from durable Flutter incident history; only the
returned scheduled timestamp is added to the existing bounded occurrence
summary.

## Foreground/history semantics

`IncidentHistoryEntry` adds the optional backward-compatible
`scheduled_observed_at` field. Existing saved history without the field still
loads unchanged. Later foreground observations preserve the newest scheduled
timestamp, and occurrence closure preserves it as historical context.

Only a complete authenticated foreground refresh may still mark a missing
occurrence as no longer observed. Scheduled evidence never reopens or resolves
an occurrence by itself. Foreground notification delivery remains based on new
foreground history occurrences and continues to use the existing shared native
cross-mode cooldown ledger.

The Incidents copy now accurately describes scheduled monitoring rather than
claiming it does not exist, and a History card shows when the same occurrence
was also observed by scheduled Android monitoring.

## Privacy and failure behavior

- Maximum correlation candidates per foreground handoff: **128**.
- Maximum hashes per native component: **128**.
- Native preference keys remain profile-hash scoped.
- Malformed native correlation JSON or hashes fail closed to no correlation.
- A native bridge/correlation failure is ignored by `AppController`; it cannot
  alter current health, history closure, notification delivery or authorization.
- Profile/schedule disable, profile deletion/edit cleanup and rule
  reconfiguration clear the corresponding scheduled state through the existing
  lifecycle.
- Android app backup remains disabled.

## Validation added

Exact-head pull-request validation passed in **Docs and Android checks #713**
(run `43498204295`, commit
`b65968b4d7b53ff2eac4a3d6bb34ed5372c57df5`). The gate passed documentation,
premium-catalog and source/privacy checks, the Python delivery regression suite,
generated-Android hardening and lockfile checks, pinned Dart formatting,
`flutter analyze --fatal-infos`, **426 Flutter tests**, and debug APK
compilation.

- Flutter bridge regressions cover exact node/task/rule candidate handoff,
  omission of incidents without an exact identity, response allowlisting and
  the 128-candidate bound.
- Incident-history regression covers scheduled timestamp persistence,
  backward-compatible round-trip behavior, preservation/newest-observation
  semantics, closure preservation, and confirms a task UPID is absent from the
  serialized history.
- Repository source checks assert the native correlation preference is
  hash/timestamp-only, the bridge exists, and the controller consumes correlation
  without changing the foreground health contract.
- The normal PR gate remains authoritative for future changes; the exact-head
  evidence above is the validation record for this implementation milestone.
- The verification-record-only follow-up commit is rerun through that same gate
  before the branch is promoted to `main`.

## Still gated

This is exact cross-mode correlation, not a general event warehouse. It does not
materialize incidents that disappeared before the app opens, correlate unrelated
resources/tasks into causal chains, provide richer time-window rules,
resource-specific notification links, relay/webhook delivery, critical paging
guarantees, or production release certification. Physical Android
foreground/WorkManager races and live PVE 8.4/9.2 partial-visibility/ACL behavior
remain release evidence gates.
