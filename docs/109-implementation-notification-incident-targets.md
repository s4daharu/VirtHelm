# Implementation milestone — bounded opaque incident notification target (0.1.64)

Date: 2026-11-14  
Scope: EP-ALERT / Android notification-navigation follow-up

## Milestone

VirtHelm now supports a bounded, privacy-preserving target for a foreground
incident notification when exactly one newly created foreground incident
occurrence can be mapped back to exactly one currently identifiable live
incident.

The notification still opens the unlocked **Incidents** destination first. The
new target only narrows that inbox to the matching current incident. It does
not automatically open a node, guest, storage or task page and never authorizes
a server read or mutation.

This is a follow-up to the generic [AND-010 notification navigation
milestone](101-implementation-notification-incident-deep-link.md) and the
bounded exact [foreground/scheduled correlation
milestone](108-implementation-cross-mode-incident-correlation.md).

## Target contract

A foreground notification receives an exact incident key only when one new
durable occurrence exists and that occurrence fingerprint maps uniquely to one
of the first 128 current live incidents. Multiple new occurrences, missing
identity or ambiguity deliberately produce the existing generic Incidents
notification.

Native Android derives a target as:

- SHA-256-derived profile key;
- the fixed category label `notification`; and
- the exact foreground incident key.

Only the resulting lowercase 64-hex digest is placed in the explicit immutable
notification `PendingIntent`. The intent does not contain a raw profile ID,
node name, guest identity, VMID, storage ID, task UPID, rule ID, endpoint,
credential, threshold, log or PVE response.

The PendingIntent always overwrites the target extra, including with an empty
value for generic notifications, so `FLAG_UPDATE_CURRENT` cannot accidentally
reuse an older targeted notification value.

## Unlock and resolution behavior

On cold launch or warm `onNewIntent`, native Android forwards only a generic
open request plus the optional opaque target digest to Dart. The app then:

1. opens the Incidents destination;
2. takes at most 128 incident keys from the current active profile/session;
3. hands those exact current keys to native code in memory for digest matching;
4. accepts only a single matching key that was in the submitted candidate set;
5. rechecks active profile, connection generation and current incident
   membership after the asynchronous match; and
6. focuses the current needs-review or acknowledged card only after all those
   checks succeed.

If the target is malformed, missing, stale, ambiguous, belongs to another
profile/session, disappears during resolution, or bridge resolution fails, the
request safely remains the generic Incidents destination.

The focused card still uses the existing guarded drill-down logic. A later user
tap must independently find exactly one matching current guest/storage/task/node
under the same profile and connection generation before any detail page opens.

## Scheduled notifications

WorkManager scheduled notifications remain deliberately generic in 0.1.64.
The scheduled path calls the targetless PendingIntent constructor, which also
clears any prior target extra. Scheduled hashed evidence is historical
correlation context and is not promoted into a resource-navigation authority.

A future scheduled target would require exact occurrence attribution without
weakening the current incomplete-read, stale-evidence and privacy boundaries.

## Race and lifecycle behavior

Warm intents use a monotonically increasing in-process navigation sequence. A
late success callback for an older notification tap cannot clear a newer pending
navigation request.

The Shell consumes each request once. A new request recreates the Incidents tab
even when Incidents is already selected, so a fresh target cannot be silently
ignored. Recreating the shell without another request does not replay the
consumed target.

No target digest or raw incident key is persisted by Flutter. Android app backup
remains disabled.

## Privacy and safety invariants

- Maximum current incident candidates per resolution: **128**.
- Only a lowercase 64-hex digest may be carried in the notification intent.
- Raw incident keys cross only the in-process Flutter/native method channel for
  notification creation or target resolution.
- Scheduled notifications remain generic.
- Target resolution cannot select/switch a connection.
- Target resolution cannot acknowledge/resolve an incident.
- Target resolution cannot change health, history or notification cooldown
  state.
- Target resolution cannot perform PVE I/O or authorize a mutation.
- Malformed native data and bridge failures fail closed to generic navigation.
- Existing lock-screen privacy and generic notification text remain unchanged.

## Regression coverage

The implementation adds or extends regressions for:

- pending native request parsing with a valid opaque target;
- malformed target fallback to generic navigation;
- the 128-candidate native resolution bound and result allowlist;
- invalid target rejection before native handoff;
- controller profile/session/current-incident revalidation;
- widget-level focus of exactly one matching current incident;
- one-shot shell consumption and warm-shell navigation;
- optional foreground incident-key handoff and malformed-key rejection;
- generated Android and repository source assertions that permit only the
  opaque target extra and forbid raw resource fields in that intent payload.

## Validation

Exact-head source validation passed in **Docs and Android checks #729**
(run `43522200949`, commit
`db2954def0ddb0bc5306f72c5fdd9324b0431829`). The gate passed
documentation/premium/source/privacy checks, the Python regression suite,
generated Android hardening, lockfile integrity, pinned Dart formatting,
`flutter analyze --fatal-infos`, **431 Flutter tests**, and debug APK
compilation.

This verification-record-only follow-up must pass that same exact-head gate
before promotion to `main`; physical-device/OEM and live PVE release evidence
remain separate gates.

## Still gated

This is a bounded exact-current-incident focus, not a general resource deep-link
system or event warehouse. Scheduled resource targets, direct automatic
resource-page navigation, materializing vanished incidents, causal/cross-resource
incident timelines, relay/webhooks, critical paging guarantees, physical Android
notification-tap/OEM validation and live PVE 8.4/9.2 release validation remain
gated.
