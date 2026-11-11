# Durable profile-scoped incident history — ALERT-02 milestone (0.1.51)

## Operator outcome

The Android Incidents tab now adds a fourth **History** view beside Needs review,
Acknowledged and Earlier. History survives reconnects and app restarts for the
same saved connection while remaining visually and semantically separate from
current health. The live badge, severity summary, mutation safety and current
incident list continue to use only foreground observations.

Up to **80 occurrence summaries per profile** are retained on-device. History
cards are read-only: they cannot open a stale task, resource or mutation route
and cannot be acknowledged as though they were current. Existing search,
severity and source filters also apply to History so the extra capability does
not turn the narrow mobile screen into another dense control surface.

## Persistence and privacy boundary

History is non-secret local metadata in SharedPreferences under the saved
profile. Android application backup remains disabled by the hardened runner.

Persisted occurrence summaries intentionally omit:

- PVE task UPIDs;
- task-log lines or task-log pages;
- credentials, API tokens or request/response bodies;
- connection endpoints;
- live authorization or write-safety state.

A task history fingerprint uses bounded display metadata (node, task title and
observation time), never the UPID. This is a local correlation aid, not an
authoritative server event identity. Node and foreground-rule history similarly
uses bounded source/target metadata. Stored titles/details and resource names
may still describe local infrastructure, so profile deletion purges this
history together with the profile's other local metadata.

## Lifecycle integrity

- A first observed signal creates a local occurrence summary with a generated
  occurrence ID that does not embed the incident key or task UPID.
- Reconnect resets live acknowledgement state. A previous review timestamp can
  remain in History as context, but it never auto-acknowledges a live signal.
- An open persisted occurrence remains open through incomplete storage/task
  coverage, malformed inventory, network loss and other partial evidence.
- Only the same complete authenticated foreground refresh already trusted by
  session triage may mark a missing occurrence as no longer observed.
- "No longer observed" is not "recovered". Task history explicitly says that
  leaving the bounded task view does not change the task outcome.
- Reappearance after a closed occurrence creates a fresh occurrence ID.
- History is capped newest-first at 80 records per profile. It never feeds the
  current incident builder, badge counts, permission checks or mutation gates.
- Local history persistence failures are best-effort only; they cannot alter
  server health, task outcomes or write authorization.

## Mobile UX

The existing phone-oriented workflow is preserved rather than expanded with a
new screen: History is another triage chip within the Incident inbox. The
severity/source filters stay behind the collapsed **Refine results** control,
search remains directly available, and history cards use readable
theme-scaled severity labels with no stale navigation affordance.

The explanatory copy now distinguishes three concepts:

1. **Needs review / Acknowledged** — current foreground signals with
   session-local operator annotations.
2. **Earlier** — departures remembered only for the current connection
   session.
3. **History** — bounded profile-scoped on-device occurrence summaries that
   survive reconnects but are never proof of current health or recovery.

## Automated acceptance

New regressions cover:

- serialized durable task summaries containing no task UPID;
- incomplete evidence preserving an open occurrence;
- complete evidence closing a missing occurrence without claiming recovery;
- reappearance creating a distinct occurrence;
- newest-first 80-record retention;
- profile isolation and purge on connection deletion;
- a read-only History mobile card remaining separate from the live incident
  count.

Run pinned Flutter 3.44.4 formatting, analyzer, full tests and Android debug
build in CI for the merge commit. These synthetic checks do not replace
physical Android TalkBack/large-text/performance validation or the required PVE
8.4/9.2 compatibility matrix.

## Still gated

Quiet hours, cooldown/suppression policy, authoritative cross-resource event
correlation, Android background checks, native notifications, relay delivery
and production release validation remain gated. This milestone does not add a
background service or any new PVE endpoint.
