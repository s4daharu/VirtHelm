# Implementation milestone — bounded wall-clock threshold duration windows (0.1.66)

Date: 2026-11-18

Scope: ALERT-006 follow-up / foreground and opted-in Android scheduled threshold rules

## Milestone

Threshold rules can now require a **minimum wall-clock duration** in addition to
their existing consecutive-sample and hysteresis controls. A rule fires only
when both conditions hold:

- at least `consecutiveSamples` usable samples at or above the firing threshold
  have been collected; and
- the time between the first usable breaching sample and the current usable
  breaching sample is at least `minimumDurationSeconds`.

The duration range is **0–3600 seconds** (0–60 minutes) and defaults to `0`.
Zero reproduces the pre-0.1.66 behavior exactly. The rule editor exposes
`No minimum`, 5, 10, 15, 30 and 60 minutes.

The same semantics apply to the foreground engine and to the opt-in native
Android scheduled worker for node-CPU, guest-CPU and storage-usage rules. This
introduces no new PVE endpoint, Android permission, relay, credential write or
mutation authority.

## Rule contract

- Persisted JSON adds `minimum_duration_seconds`.
- Missing field, or a saved rule created before 0.1.66, decodes as `0`.
- Non-integer, negative or greater-than-3600 values are rejected by the Dart
  decoder instead of being clamped silently.
- Native scheduled payload adds `minimumDurationSeconds` to all three rule
  categories.
- Native `fromChannel`/`fromJson` accept the missing field as `0` so an older
  persisted worker secret cannot fail closed after an app update; invalid
  values in the range check still reject the rule.
- Native rule validation requires `minimumDurationSeconds in 0..3600`.

## Foreground semantics

- The window starts at `Inventory.fetchedAt` of the first usable breaching
  sample for that rule.
- Confirmation advances only for strictly newer foreground snapshots. A
  repeated `fetchedAt` — the same read evaluated twice — cannot count twice and
  cannot stretch the window.
- Any missing or unusable sample removes pending confirmation and its window.
- An already-active incident is unaffected: it still resolves only through the
  existing hysteresis boundary. Missing data never resolves it.
- Firing requires a later usable breaching sample whose timestamp is at least
  `pendingSince + minimumDurationSeconds`.
- The fired incident detail mentions the required seconds when the duration is
  positive.

The foreground window is measured on the device clock and only advances when a
new foreground snapshot is evaluated. A long auto-refresh interval therefore
produces an interval-quantized result: the duration is a **lower bound observed
at evaluation time**, not a timer or a delivery guarantee.

## Scheduled semantics

- The native worker evaluates rules during an existing WorkManager run and uses
  that run's `System.currentTimeMillis()` as `nowMs`.
- Runtime state gains `pendingSinceMs` and `lastSampleMs` next to the existing
  `pending` counter and `active` boolean.
- A run whose timestamp is not strictly newer than the last sample cannot
  double-count confirmation, mirroring the foreground guard.
- State written before 0.1.66 has no timestamps; it restarts the window from the
  next breaching sample instead of crashing or firing immediately.
- Missing, ambiguous or malformed samples reset pending confirmation but do not
  resolve an active rule, preserving the existing scheduled policy.
- A new incident is still reported only on a false-to-active transition, so a
  rule that remains active is not re-notified by the duration path.
- Android WorkManager's minimum repeat interval is 15 minutes and execution is
  inexact. The 5- and 10-minute editor options can therefore not fire at exactly
  5 or 10 minutes in scheduled mode; the configured duration remains a lower
  bound that is checked at the next run. The editor's foreground wording does
  not claim an exact scheduled delivery time.

Device wall-clock changes (manual time changes or NTP step adjustments) affect
the window. A backward clock change cannot advance or shorten confirmation
because non-increasing timestamps are ignored; a forward jump can satisfy the
window earlier in monotonic terms. This is a bounded local heuristic, not a
certified time source.

## Persistence and privacy

- Foreground rule configuration continues to use profile-scoped non-secret
  SharedPreferences metadata. Pending counters and windows remain runtime-only
  and are cleared on profile switch, reconnect and dispose.
- Native runtime state still stores only a SHA-256-derived rule ID plus
  `pending`, `active`, `pendingSinceMs` and `lastSampleMs`.
- No node names, guest identities, VMIDs, storage IDs, thresholds, samples,
  credentials, logs or PVE responses are added to runtime state, notifications
  or navigation payloads.
- The existing 32-rule synchronization bound is unchanged.

## Safety invariants

- The duration control can only delay a new firing; it cannot create, resolve
  or acknowledge an incident on its own.
- It cannot change health, severity, hysteresis clearing or resource drill-down
  authorization.
- It performs no PVE I/O and cannot authorize or replay a mutation.
- No POST/PUT/PATCH/DELETE path was added; scheduled checks remain the same
  bounded GET-only reads with redirect blocking and no immediate retry.
- Malformed or out-of-range configuration fails closed at decode/validation.

## Regression coverage

Dart regressions cover:

- JSON round-trip, legacy defaults and rejection of negative, oversized and
  non-integer durations;
- a minimum window that does not fire before the configured elapsed time and
  fires once it is reached;
- a repeated snapshot timestamp that cannot satisfy two required samples;
- a missing sample that restarts a duration window;
- existing consecutive-sample and hysteresis behavior;
- the editor's new duration control and list summary;
- all three scheduled MethodChannel payloads carrying
  `minimumDurationSeconds`.

Native source and generated-runner guards assert:

- bounded validation, channel defaults and JSON defaults for the new field;
- persisted `pendingSinceMs`/`lastSampleMs` alongside hashed rule IDs only;
- strict timestamp monotonicity before confirmation advances;
- the shared state-machine helper that enforces both sample count and elapsed
  duration for all three rule categories.

There is no JVM/Robolectric behavioral suite for the native worker in this
repository; debug APK compilation plus these source guards are the local native
evidence. Physical Android background execution remains a release gate.

## Validation

Local validation on 2026-11-18 used the available Flutter 3.47.5 SDK and Java 21
(the repository still pins Flutter 3.44.4 and Java 17 for CI):

- `dart format --output=none --set-exit-if-changed lib test` (no changes)
- `flutter analyze --fatal-infos --no-pub` (no issues)
- `flutter test` (436 runtime tests passed)
- `python3 scripts/check_docs.py` (84 required files)
- `python3 scripts/check_premium.py` (16 docs, 200 planned features)
- `python3 scripts/check_source.py`
- `python3 scripts/check_android_generated.py`
- `python3 -m unittest discover -s scripts/tests -v` (20 regressions passed)
- throttled debug APK compilation (142.1 s, `app-debug.apk` produced)

All listed local checks passed. The local toolchain differs from the pinned CI
Flutter 3.44.4/Java 17 toolchain; exact-head pinned CI remains authoritative.

## Still gated

This is a bounded local duration window, not a paging or SLA guarantee. Exact
timer evaluation, long historical windows, maintenance-window suppression,
multi-sample interval statistics, relay/webhooks, critical paging guarantees,
physical Android Doze/OEM validation and live PVE 8.4/9.2 fixture validation
remain gated.
