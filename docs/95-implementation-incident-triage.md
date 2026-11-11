# Foreground incident triage — ALERT-02 partial (0.1.49)

## Scope and operator outcome

The mobile Incidents tab now separates **Needs review**, **Acknowledged**,
and **Earlier** signals. Operators can acknowledge or undo acknowledgement
using a full-width-accessible action without opening the incident's task,
guest, storage or node detail route. Severity filters and all existing
drill-downs remain. The inbox continues to display stale and partial task
coverage warnings and shows the total actual active incident count even
when every signal is acknowledged.

This closes a bounded **session-local** portion of ALERT-02. It is **not**
durable incident management, server-side acknowledgement, event correlation
across sessions, remediation or recovery verification.

## Lifecycle and integrity boundary

- A signal has an identity from the existing conservative node/task/rule
  incident builder; no new PVE endpoint is used.
- First observation opens an unreviewed record. Repeated observations of
  the same active key preserve the acknowledgement.
- A user acknowledgement is local state only. It **does not** modify the
  underlying `CockpitIncident`, its severity, rule engine or task outcome.
  The Home badge and severity summary continue showing all actual signals.
- A **complete authenticated foreground inventory and supplemental storage/
  task read** is required before a missing key can leave the active ledger.
  Partial task/storage reads, malformed inventory and auth/network failures
  are explicitly forbidden from advancing a missing signal to Earlier.
- For task signals, Earlier means *no longer in bounded task view*;
  it does **not** mean task success or recovery. For node/rule signals, it
  means only *not observed in the latest complete foreground refresh*.
- Reappearance after departure starts a fresh unacknowledged occurrence.
  Acknowledgements are scoped to the active profile and connection generation
  and rejected if either changed since the UI rendered.
- Earlier observations are capped at **40** in memory; active signals are
  retained without an artificial cap. Reconnect, profile change, removal
  and controller disposal erase the ledger and all task identifiers.
- No persistence, background checking, Android notifications, PVE mutations
  or credentials are added. A task UPID may exist in RAM only for the active
  connection and is never written to preferences or files.

## Mobile UX and testing

The inbox now uses large labelled triage chips, keeps the existing severity
chips, leaves the entire incident row tappable for source drill-down, and
adds a dedicated clearly labelled Acknowledge / Mark as unreviewed action
separate from navigation. Earlier cards are read-only so an expired task
link cannot be opened as though it remained current.

Pure Dart/Flutter ledger tests cover acknowledgement invariance, incomplete
evidence, return/rearm, task departure wording, bound/reset and invalid
acknowledgement. A widget regression covers moving a node signal between
Needs review and Acknowledged without hiding the actual incident.

Run pinned Flutter 3.44.4 formatting, analyze, tests and Android debug build
through CI; synthetic tests are not physical-phone accessibility signoff.

## Still gated

Persistent profile-scoped history, cross-session dedup/occurrence identity,
alert quiet hours and cooldown, state-machine lifecycle evidence, OS
notification privacy, WorkManager/relay, 8.4/9.2 permission/partial-ACL
fixtures and Android TalkBack/large-text/performance field validation remain
deferred. Neither this local feature nor a passing CI run is production
certification.
