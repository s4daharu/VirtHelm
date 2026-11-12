# Android incident notification deep link — AND-010 milestone (0.1.55)

## Operator outcome

VirtHelm incident notifications now open the in-app **Incidents** destination
instead of only launching the app at its default Home tab.

The behavior is deliberately broad and privacy-preserving. The notification
does **not** identify a profile, node, guest, storage, task, rule or specific
incident. Tapping the notification only requests the generic Incidents tab.
The app then renders whatever incident state is valid for the currently
selected connection and current connection generation.

This applies to both:

- foreground incident notifications; and
- opted-in Android WorkManager scheduled node-state incident notifications.

## Android navigation contract

Both notification paths use one explicit immutable `PendingIntent` targeting
`MainActivity`. Its only navigation marker is the package-scoped action:

`com.s4daharu.virthelm.action.OPEN_INCIDENTS`

The intent contains no resource selector and no `putExtra` payload.

The intent uses `FLAG_ACTIVITY_CLEAR_TOP | FLAG_ACTIVITY_SINGLE_TOP` so the
single-activity Flutter app can reuse an existing activity and receive
`onNewIntent()`. The pending intent remains `FLAG_IMMUTABLE`.

VirtHelm does not use a notification trampoline, broadcast receiver, exported
implicit URI, full-screen intent, action button, or background unlock bypass.
Android remains responsible for device-unlock policy before the activity is
shown.

## Cold and warm launch behavior

For a cold launch, Flutter asks the native bridge whether the activity was
started by the incident action and consumes that marker once.

For an already-running activity, `MainActivity.onNewIntent()` forwards a
generic `openIncidents` event over the private app method channel. If Dart is
not ready to receive the event, native code retains a pending boolean and
Flutter also checks for a pending request when it resumes.

The Flutter controller stores only a monotonic in-memory navigation request
counter. No incident identifier or profile ID is persisted. `ShellPage`
listens for a new request and selects the Incidents navigation destination.
A request received before the shell exists is honored when the shell is first
constructed after connection selection/initialization.

## Security and privacy boundary

Notification deep linking must never become an authorization mechanism.
Opening Incidents does not:

- select or switch a connection;
- make a PVE request by itself;
- acknowledge, resolve or mutate an incident;
- bypass current profile/generation checks;
- expose task logs or infrastructure identifiers in Android intent data;
- change foreground/background notification privacy;
- weaken the hidden-by-default secure-lock-screen policy from ALERT-010.

Resource drill-down remains controlled by the existing in-app incident UI,
which resolves targets only against the current live/session state.

## Automated acceptance

Tests and source assertions cover:

- pending notification navigation selecting Incidents when the shell is first
  created;
- a warm notification switching an existing shell from another tab to
  Incidents;
- the Flutter/native navigation channel contract;
- generated Android source handling `onNewIntent()` and cold pending intent
  consumption;
- one shared immutable content intent for foreground and scheduled
  notifications;
- absence of `putExtra` in the notification-navigation intent builder;
- continued absence of public lock-screen visibility.

Pinned formatting, analyzer, Flutter runtime tests and debug APK compilation are
the authoritative merge checks.

## Remaining gates

Physical Android validation still needs to cover notification taps from a
secure lock screen, cold process start, warm foreground/background activity,
multiple taps, OEM notification behavior and operator channel overrides.

This milestone intentionally stops at the generic Incidents destination.
Resource-specific notification payloads/deep links remain out of scope.
Background failed-task/threshold parity, cross-mode notification
deduplication, authoritative cross-resource correlation, optional relay
delivery and production critical-alert guarantees remain gated.
