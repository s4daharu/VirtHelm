# Implementation milestone — bounded same-node incident context (0.1.67)

Date: 2026-11-19

Scope: EP-ALERT richer cross-resource correlation, bounded foreground slice

## Milestone

The current unlocked foreground incident inbox now derives **same-node related
signal context** across the three existing live incident sources:

- node inventory state;
- failed or unknown task state; and
- saved foreground threshold rules.

When at least two current incidents share one **exact node identity** and span at
least two source types, each affected card shows the number of other current
signals on that node and the source categories they represent.

This deliberately does **not** claim that one signal caused another. It is a
bounded operator-orientation aid for the current session only.

## Correlation contract

- Only current in-memory `CockpitIncident` values are candidates.
- At most `128` unique incident keys are considered.
- Duplicate keys are ignored before grouping.
- Incidents with no node identity are excluded.
- Node identity matching is exact; no fuzzy host/resource matching is added.
- A node group must contain at least two incidents and at least two different
  `CockpitIncidentSource` values.
- Same-source-only task clusters are not presented as richer cross-resource
  correlation.
- Each card reports only related-count and source-category context; it does not
  expose a new persisted identifier or relationship graph.

## Authority and safety

The related-signal hint is presentation context only. It cannot:

- create, resolve or acknowledge an incident;
- change severity, health, durable history, notification cooldown or scheduled
  evidence;
- perform PVE I/O or add any endpoint;
- authorize guest/node/storage/task drill-down;
- retry or replay a mutation; or
- certify root cause, recovery or continuous monitoring.

All existing profile/generation/live-resource checks remain the only authority
for navigation and operations.

## Privacy and persistence

No new persistence field is added to `IncidentHistoryEntry`,
SharedPreferences, secure storage, Android native preferences, notification
payloads or scheduled correlation state.

The calculation uses only the node/source metadata already present in the
current incident objects. It is rebuilt when the inbox renders and disappears
with the current session. Task UPIDs remain excluded from durable History.

## UI behavior

A related-signal line appears only on affected current incident cards, for
example:

`2 related current signals on pve1 • Task history + Foreground rule.`

Every line ends with an explicit warning that the shared node is context only
and **does not prove causality**. Existing search, source/severity filters,
acknowledgement and notification focus continue to operate on the underlying
incident itself.

## Regression coverage

Dart regressions cover:

- exact same-node node/task/rule grouping across different source types;
- omission of same-source-only clusters;
- omission of incidents without a node identity;
- deterministic source summaries; and
- the 128-candidate bound.

Widget coverage verifies that two cross-source incidents on the same node show
the non-authoritative context while no durable history is created by rendering
that relationship.

## Validation

The execution environment used for this implementation has Java 21 available
but no Flutter or Dart executable and cannot clone GitHub directly. Before
branch publication the implementation transform validates exact source anchors,
parses the updated `PROJECT_STATUS.json`, and checks the bounded correlation
contract structurally.

The repository's pull-request workflow is therefore the authoritative pre-merge
gate. It pins Flutter 3.44.4 and Java 17 and runs documentation/premium/source
checks, generated Android hardening validation, Dart formatting,
`flutter analyze --fatal-infos`, the full Flutter test suite and a debug APK
build.

## Still gated

This is not a causal engine or historical topology. Richer temporal/cross-node
correlation, maintenance-window suppression, relay/webhooks, critical paging,
physical Android validation, PVE 8.4/9.2 fixture validation and production
release certification remain gated.
