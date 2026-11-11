# Mobile incident discovery and guarded batch review — 0.1.50

## Operator outcome

The Android Incidents tab now supports foreground-only text search across
already-loaded titles, details, sources, node names and task/resource IDs.
Operators can combine a node/task/rule chip with severity and triage views.
The unfiltered health counters and navigation badges are not suppressed by
UI filters.

The Needs review view can acknowledge **only its filtered records** after a
confirmation naming the count. The controller checks the rendering profile ID
and connection generation after the dialog, intersects selected identities
with currently observable incidents, deduplicates keys, and updates the
session-only ledger once. Signals that departed, disappeared from the
current live view or belong to another session are not batch-acknowledged.
A collapsed, accessible Refine results panel keeps severity/source chips off
the initial viewport until needed. A reset-filters action prevents misleading
empty views. Mobile incident cards
now show severity as normal-size theme-scaled text rather than a 9px label
beside the navigation chevron.

## Safety, truth and privacy

- Acknowledgement remains a **local operator annotation**. It never marks
  resources healthy, dismisses real alerts, changes task outcomes, performs
  remediation or submits a PVE request.
- Keys are captured at confirmation-open time; newly arriving signals are
  not silently selected. The exact session and live set are rechecked after
  the dialog closes.
- All search/filter actions are local; no additional reads, writes, timers,
  persistence, credentials, server acknowledgements or Android notification
  services are introduced.
- Only complete authenticated foreground reads can move a missing signal to
  Earlier. Bounded session history and reset on reconnect remain unchanged.

## Automated acceptance

- Pure ledger regression: deduplication, already-acknowledged and earlier
  records cannot receive a new batch annotation.
- Controller regression: wrong generation/profile are rejected and only
  current keyed signals change.
- Widget regression: search filters the batch target set, confirmation
  changes only selected incidents, reset restores visibility and source
  filtering reports an honest empty result.
- Synthetic 320dp/200%-text mobile incident layout check.

Run the pinned Flutter 3.44.4 formatter, analyzer, full tests and debug APK
checks on this commit. Automated checks do not replace physical Android
TalkBack, screenshots, 200-incident responsiveness, network-transition or
live PVE 8.4/9.2 compatibility evidence.

## Deferred

The full ALERT-02 state machine, persistent history, quiet hours/cooldown,
durable occurrence IDs, cross-session correlation, native notifications and
relay remain gated, not silently claimed as complete.
