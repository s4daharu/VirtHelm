# Bounded Operator-Started Maintenance Notification Silence

## Milestone

VirtHelm 0.1.68 closes the next bounded EP-ALERT gap after same-node current
incident context: an operator can temporarily silence Android incident
**delivery** for one saved connection while planned work is under way.

This is deliberately not a maintenance scheduler or a Proxmox maintenance-state
integration. The operator starts the window now and chooses one of four bounded
durations: 1, 4, 12 or 24 hours.

## Implemented behavior

Settings > Incident notifications exposes profile-scoped controls to:

- start a 1-hour, 4-hour, 12-hour or 24-hour silence immediately;
- replace an active window by starting a new bounded window from now; and
- end the active silence early.

While the window is active, both foreground Mode A and opted-in WorkManager
Mode B skip Android incident notification delivery for that profile. Incidents
still appear in the current inbox, durable occurrence history continues to be
captured, current health/severity is unchanged, acknowledgement and triage are
unchanged, scheduled GET checks still execute, and cross-mode correlation
evidence can still be updated. A suppressed occurrence is not queued for later
notification.

## Persistence and native enforcement

Dart persists one non-secret UTC expiry timestamp under the saved profile ID.
The existing native delivery ledger persists only:

- the SHA-256 profile key already used for cross-mode notification cooldown; and
- the maintenance-silence expiry timestamp.

The native ledger checks maintenance before its shared cooldown and post
boundary. That makes the rule effective for foreground delivery and for
WorkManager after the Dart isolate has stopped.

Native updates reject a non-zero expiry that is already elapsed or more than
24 hours in the future. Expired, malformed-type or out-of-range stored values
fail open and are cleared rather than extending silence indefinitely. Full
profile cleanup removes both the cooldown and maintenance entries. Dart also
rejects setter values outside the same future-only 24-hour bound.

## Safety and privacy boundary

This milestone adds no PVE request, endpoint, permission, polling interval,
mutation, retry, relay or background credential access. It does not change
incident creation, resolution, history closure or write authorization.

The saved expiry contains no infrastructure identity. The native worker keeps
no plaintext profile ID for this feature. Notification payload privacy,
lock-screen policy, opaque incident targeting and cross-mode cooldown behavior
remain unchanged.

The UI explicitly describes the feature as notification-only. It never labels a
node, guest, storage or PVE cluster as being in maintenance mode.

## Regression coverage

The new Flutter regressions cover:

1. future-only and maximum-24-hour duration validation;
2. the Android MethodChannel payload shape (profile ID plus expiry only);
3. profile-scoped expiry persistence and deletion cleanup;
4. controller apply/persist/clear behavior and profile mismatch rejection; and
5. the Settings controls for all bounded durations plus early termination.

Repository source assertions additionally require the profile metadata key,
controller delivery guard, native ledger prefix/check, MainActivity bridge,
Settings control key and this milestone document.

## Validation status

Exact feature head `494e7688823e488b3caf38473989dc0b6f747c04` on PR #69
passed both pull-request workflows:

- Docs and Android checks run `44402373118` passed documentation, premium,
  source/security assertions and the Python delivery-test suite.
- Android CI run `44402373082` passed the same repository checks, hardened
  generated-runner/lockfile verification, pinned Dart formatting,
  `flutter analyze --no-pub --fatal-infos`, all **444 Flutter runtime tests**,
  and the ARM64 debug APK compile.
- The maintenance slice contributes five dedicated Flutter test declarations.

The implementation environment itself has no outbound Git network checkout and
no local Flutter/Dart SDK, so the repository/runtime evidence above comes from
the exact GitHub feature head rather than being mislabeled as a local pass. A
small verification-record follow-up changes documentation/status only; the
verified application tree is unchanged.

Physical Android notification delivery, process-death/WorkManager timing,
clock-change behavior, secure-storage/device lifecycle and the PVE 8.4/9.2
release matrix remain open release gates.

## Deferred

This slice intentionally does not implement future-start windows, recurring
maintenance calendars, per-resource silence scopes, automatic/server-derived
maintenance detection, catch-up notification queues, relay/webhooks or richer
causal cross-resource timelines. Those require separate product, safety,
timezone/DST and backend evidence.
