# Implementation milestone — bounded scheduled incident notification target (0.1.65)

Date: 2026-11-16

Scope: EP-ALERT / Android scheduled-notification navigation follow-up

## Milestone

VirtHelm now supports the same bounded, privacy-preserving incident focus for
an Android **scheduled** notification that 0.1.64 introduced for foreground
notifications. A WorkManager run that observes exactly one new, exactly
attributable incident may carry one opaque target digest in its notification
`PendingIntent`. Tapping it still opens the unlocked **Incidents** destination
first and only narrows the inbox when the matching incident is still current
for the active profile and connection generation.

Scheduled notifications remain generic in text, category, lock-screen
visibility and payload. The new target is navigation context only: it cannot
authorize a read, select a connection, acknowledge or resolve an incident, or
perform any PVE mutation.

This is a follow-up to the [bounded opaque foreground notification target
milestone](109-implementation-notification-incident-targets.md) and the
[bounded exact cross-mode correlation
milestone](108-implementation-cross-mode-incident-correlation.md).

## Attribution contract

The worker emits a target only when the run's new-incident set is exactly one
unique exact identity:

| New component | Exact identity | Source tag |
|---|---|---|
| Node state | exact node name | `node` |
| Failed recent task | exact task UPID | `task` |
| Node/guest/storage threshold rule | exact saved rule ID | `rule` |

Attribution tracks only identities that are **new in this run**: a node entering
the incident state, a failed task newer than the previous task watermark, or a
rule crossing its threshold into active. Incidents that were already active
before this run do not block attribution, and a rule that stays active is not
re-reported as new.

A run remains generic when any of the following is true:

- more than one new identity is present;
- two components report new incidents in the same run;
- any enabled component read fails or is incomplete;
- the new identity list is empty, malformed, duplicated or over its bound;
- capture of a new task identity is incomplete.

The worker does not guess. A target is emitted only when the whole enabled
scheduled read completed. A failed component read could hide a second new
incident that the notification never described, so the notification stays
generic instead of focusing one known card. Even with complete reads, a
component that reports a new incident without a complete attributable identity
list also makes the notification generic.

Native Android derives the scheduled target as:

- the same SHA-256-derived profile key used by the delivery ledger and
  correlation store;
- the fixed category label `scheduled`;
- the fixed source tag (`node`, `task` or `rule`); and
- the exact scheduled identity.

Only the resulting lowercase 64-hex digest is placed in the explicit immutable
notification `PendingIntent`. The intent carries no raw profile ID, node name,
guest identity, VMID, storage ID, task UPID, rule ID, endpoint, credential,
threshold, log or PVE response.

Every notification, generic or targeted, overwrites the target extra. A later
generic notification therefore cannot inherit an older target through
`FLAG_UPDATE_CURRENT`.

## Resolution behavior

On cold launch or warm `onNewIntent`, native Android forwards only the generic
open request plus the optional opaque digest. The app then:

1. opens the Incidents destination;
2. takes at most 128 current incidents for the active profile/session;
3. supplies each current incident's key, source tag and exact identity to
   native code in memory;
4. native accepts only one candidate whose foreground or scheduled digest
   matches the intent digest;
5. rechecks active profile, connection generation and current incident
   membership after the asynchronous match; and
6. focuses the matching needs-review or acknowledged card only after all
   checks succeed.

Foreground digests remain `profileKey|notification|incidentKey`. Scheduled
digests are `profileKey|scheduled|source|identity`. Both are checked during
resolution so an existing notification created by 0.1.64 still resolves after
an app update. Ambiguous, malformed, stale, other-profile or
generation-changed candidates fall back to the generic Incidents destination.

The focused card still uses the existing guarded drill-down logic. A later user
tap must independently find exactly one matching current resource under the
same profile and connection generation before any detail page opens.

## Privacy and safety invariants

- Maximum current incident candidates per resolution: **128**.
- Maximum scheduled rule identities per notification remains the existing
  32-rule synchronization cap.
- Only a lowercase 64-hex digest may be carried in the notification intent.
- Raw incident keys, sources and identities cross only the in-process
  Flutter/native method channel for target resolution.
- Scheduled notification text, category and lock-screen privacy are unchanged.
- Target resolution cannot select/switch a connection.
- Target resolution cannot acknowledge/resolve an incident or change history.
- Target resolution cannot change health, delivery cooldown or scheduled state.
- Target resolution cannot perform PVE I/O or authorize a mutation.
- Malformed native data and bridge failures fail closed to generic navigation.
- Native source/identity validation is bounded and control-character rejecting.

## Regression coverage

Dart regressions cover the shared bridge/controller path:

- foreground digests and new scheduled candidates resolve through one bridge;
- source/identity candidate handoff for node and failed-task incidents;
- the 128-candidate native resolution bound and allowlist;
- malformed source tags, identities and target digests failing closed;
- controller profile/session/current-incident revalidation unchanged.

Native source and generated-runner guards assert:

- scheduled attribution uses only newly active rule IDs and new failed-task
  identities, never the broader currently-active lists;
- generic fallback wiring for missing new identities and incomplete captures;
- the navigation intent carries only the opaque target extra and never a raw
  resource field;
- scheduled and foreground digests share the bounded resolver and profile key.

There is no JVM/Robolectric behavioral suite for the native worker in this
repository; debug APK compilation plus those source guards are the local native
evidence. Physical Android taps remain a release gate.

## Validation

Local validation on 2026-11-16 used the available Flutter 3.47.5 SDK and
Java 21 (the repository still pins Flutter 3.44.4 and Java 17 for CI):

- `dart format --output=none --set-exit-if-changed lib test` (73 files, no
  changes)
- `flutter analyze --fatal-infos --no-pub` (no issues)
- `flutter test --no-pub` (433 runtime tests passed)
- `python3 scripts/check_docs.py` (83 required files)
- `python3 scripts/check_premium.py` (16 docs, 200 planned features)
- `python3 scripts/check_source.py`
- `python3 scripts/check_android_generated.py`
- `python3 -m unittest discover -s scripts/tests -v` (20 regressions passed)
- throttled debug APK compilation (244.2 s, `app-debug.apk` produced)

All listed local checks passed. The local toolchain differs from the pinned CI
Flutter 3.44.4/Java 17 toolchain; exact-head pinned CI remains authoritative.

Exact-head pinned CI remains authoritative for promotion. Physical-device/OEM
notification-tap behavior, WorkManager delivery timing and live PVE 8.4/9.2
evidence remain separate release gates.

## Still gated

This is bounded notification focus, not a general resource deep-link system.
Direct automatic resource-page navigation, materializing incidents that vanish
before foreground observation, causal/cross-resource timelines, richer
time-window rules, relay/webhooks, critical paging guarantees, physical
Android/OEM validation and live PVE 8.4/9.2 release validation remain gated.
