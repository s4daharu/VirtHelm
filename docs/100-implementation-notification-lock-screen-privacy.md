# Notification lock-screen privacy — ALERT-010 milestone (0.1.54)

## Operator outcome

VirtHelm now exposes one device-wide lock-screen privacy setting for incident
notifications. It applies to both foreground incident summaries and opted-in
Android WorkManager scheduled incident notifications.

The available choices are intentionally narrow:

- **Hide on secure lock screen** — default. VirtHelm requests Android
  `VISIBILITY_SECRET`, so no part of the incident notification should be
  revealed on a secure lock screen.
- **Show generic VirtHelm alert** — VirtHelm requests
  `VISIBILITY_PRIVATE`. Only the already-generic VirtHelm alert is eligible
  to appear; infrastructure-specific content is never added to the payload.

There is no `VISIBILITY_PUBLIC` option.

Android system and per-channel notification settings remain authoritative and
may further restrict what appears. This milestone does not attempt to bypass
device policy, OEM policy or operator choices.

## Privacy boundary

Both notification paths retain generic native payloads. They contain no:

- profile name or endpoint;
- node, guest, storage, rule or backup name;
- VMID;
- task UPID, task title or task log;
- API credential or authorization result;
- raw PVE response.

The lock-screen preference is non-secret device metadata. It is stored once per
installation rather than per profile because lock-screen exposure is a device
privacy policy. Android app backup remains disabled.

The default is fail-closed. Missing, malformed or unknown stored values resolve
to **Hide on secure lock screen**. Native Android state also defaults to
`VISIBILITY_SECRET` if Flutter has never synchronized a preference.

## Flutter and native synchronization

`ProfileRepository` persists the device preference in SharedPreferences.
`AppController.initialize()` loads it and synchronizes the native Android
notification bridge so WorkManager can use the same setting after the Dart
isolate exits.

When the operator changes the setting, VirtHelm first asks Android to apply the
new native value. The Dart controller and local preference are updated only
after that native operation reports success. A native application failure
therefore cannot make the UI falsely claim the privacy change took effect.

The scheduled worker reads the same native preference immediately before
building a notification. Foreground delivery does the same in
`MainActivity`.

## Channel and notification behavior

The incident channel and each posted incident notification are assigned the
selected visibility. Re-applying channel configuration is best-effort because
Android and the operator can retain or override channel-level lock-screen
settings. Per-notification visibility is still set for every new VirtHelm
incident notification.

The notification content intent continues to open VirtHelm only. This
milestone does not add a resource-specific deep link, background unlock bypass,
full-screen intent, action button or notification-carried infrastructure
identifier.

## Automated acceptance

Source/runtime tests cover:

- fail-closed parsing for missing and unknown preference values;
- persisted device preference loading;
- native synchronization during controller initialization;
- refusal to persist a setting when native application fails;
- successful native + repository update ordering;
- generated Android source containing both `VISIBILITY_SECRET` and
  `VISIBILITY_PRIVATE`;
- one shared native privacy store used by foreground and scheduled delivery;
- absence of a public lock-screen visibility path;
- Settings UI wiring for the privacy selector.

Exact-head PR run **43156373238** passed repository source/docs checks,
generated Android privacy assertions, pinned Dart formatting,
`flutter analyze --fatal-infos`, **391 Flutter runtime tests**, and debug APK
compilation. These checks verify source/build integration; they do not replace
the physical-device lock-screen gates below.

## Remaining gates

Physical Android devices must still validate secure-lock-screen behavior across
supported API levels and representative OEMs, including operator channel
overrides. Wear OS mirroring and other companion surfaces remain outside this
milestone's certification.

Notification deep links to a specific unlocked incident view remain gated
under Android polish / ALERT follow-up work. Background failed-task and
threshold-rule parity, authoritative incident correlation, optional relay
delivery and production critical-alert guarantees also remain gated.
