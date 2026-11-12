# Implementation — cross-mode notification delivery deduplication (0.1.57)

## Milestone

VirtHelm 0.1.57 closes the previously documented foreground/scheduled
notification delivery duplication gap. The implementation does **not** merge
the two alert engines or claim background parity. It adds one shared native
delivery boundary so a foreground activity notification and a WorkManager
scheduled notification for the same saved connection cannot independently
ignore the other mode's recent successful delivery.

## Operator behavior

Foreground and scheduled notifications retain their existing, independently
configured quiet hours and cooldown values. When either mode is otherwise
eligible to deliver, its own cooldown is checked against the most recent
successful Android incident notification from **either** mode for that profile.

For example, if a scheduled notification was shown five minutes ago and the
foreground cooldown is 30 minutes, a newly eligible foreground occurrence is
suppressed. The inverse is also true using the scheduled mode's configured
cooldown. A cooldown of zero intentionally disables cooldown suppression for
that mode.

Suppressed notifications are not queued for later. Delivery suppression never
changes current incident health, durable history, acknowledgement state,
threshold state, scheduled occurrence state or any mutation authorization
guard.

## Native delivery ledger

The shared ledger is implemented in the reviewed Android template used by both
MainActivity and BackgroundIncidentWorker.

The storage boundary is deliberately small:

- private MODE_PRIVATE SharedPreferences;
- one SHA-256-derived profile key;
- one last-successful-delivery timestamp;
- no raw profile ID in the native preference key;
- no profile name or endpoint;
- no incident key or source;
- no node/guest/storage/rule name;
- no VMID, UPID, task title or log;
- no credential or PVE response.

Full scheduled/profile lifecycle cleanup removes the shared timestamp. Merely
turning off one notification mode does not rewrite incident health or history.

## Concurrency and Android threading

The last-delivery check and notification post are serialized with one native
in-process lock. The current generated runner uses the ordinary WorkManager
Worker path and does not configure a remote worker process. WorkManager calls
Worker.doWork() on a background thread, while foreground delivery can arrive
on the activity thread, so the shared lock prevents both paths from passing
separate cooldown checks at the same time.

The ledger uses SharedPreferences.apply() after a successful post. Android
updates the in-memory preference immediately and writes it to disk
asynchronously, avoiding synchronous preference disk I/O on the activity main
thread.

Android references:
- https://developer.android.com/develop/background-work/background-tasks/persistent/threading/worker
- https://developer.android.com/training/data-storage/shared-preferences

## Flutter/native contract

The foreground notifier bridge now sends only:

- critical for the already-generic title choice;
- the internal profile ID so native code can derive the same SHA-256 key used by
  WorkManager;
- the foreground cooldown duration.

Invalid/empty profile identity or cooldown values outside 0–1440 minutes fail
closed before native delivery. The profile ID is bridge metadata only and is
never inserted into notification text, Android intent extras or notification
navigation state.

The scheduled worker already receives only the hashed profile key in its
WorkManager input and therefore never needs to recover the raw profile ID for
deduplication.

## Privacy, navigation and lock screen

This milestone does not expand notification content. Foreground and scheduled
payloads remain generic, ALERT-010's hidden-by-default/generic-only lock-screen
policy remains shared, and AND-010's explicit immutable content intent still
contains no profile/resource selector.

There is no public lock-screen visibility, notification action button,
full-screen intent, implicit exported URI, resource-specific deep link or
unlock bypass.

## Automated acceptance

Regression/static coverage verifies:

- foreground bridge calls include profile identity and cooldown metadata only;
- malformed deduplication bridge inputs fail closed without invoking Android;
- AppController forwards the active profile and foreground cooldown;
- both generated Android notification paths use
  IncidentNotificationDeliveryLedger;
- profile IDs are SHA-256-derived before shared native storage;
- the ledger uses private preferences and synchronized delivery;
- full native lifecycle cleanup clears the shared ledger;
- scheduled delivery still records its own last-scheduled-notification evidence
  only when a notification was actually shown;
- generic payload, immutable navigation and no-public-visibility assertions
  remain enforced.

Exact-head CI evidence is pending until the feature PR runs the repository
source/docs checks, generated Android hardening checks, pinned Dart formatting,
flutter analyze --fatal-infos, the full Flutter test suite and debug APK
build.

## Remaining gates

Physical-device validation still needs foreground/background transition races,
process death, Doze/app standby, OEM notification behavior and channel/permission
changes. This feature does not make scheduled checks exact or suitable for
critical paging.

Still gated: background failed-task/threshold-rule parity, authoritative
cross-resource incident correlation, resource-specific notification links,
optional relay/webhook delivery and production release certification.
