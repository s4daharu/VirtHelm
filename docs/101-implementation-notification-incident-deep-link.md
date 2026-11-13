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

At 0.1.55 the intent contained no `putExtra` payload. The 0.1.64 follow-up
keeps that privacy boundary for raw infrastructure identity but may add one
package-scoped extra containing only a lowercase 64-hex opaque target digest
for a uniquely identifiable foreground incident. Generic and scheduled
notifications explicitly overwrite that extra with an empty value.

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

The Flutter controller stores only a consumable in-memory navigation request.
As of 0.1.64 that request may contain the opaque target digest, never a raw
resource identifier. `ShellPage` consumes each request once and selects the
Incidents destination. The current incident set is then offered back to native
code in memory, bounded to 128 keys, for exact digest resolution. AppController
rechecks the active profile, connection generation and current incident
membership before the inbox may focus one card. A request received before the
shell exists is honored when the shell is first constructed after connection
selection/initialization; an already consumed request cannot reopen Incidents
after a later shell recreation.

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
- consumed requests not reopening Incidents after a later shell recreation;
- the Flutter/native navigation channel contract;
- generated Android source handling `onNewIntent()` and cold pending intent
  consumption;
- one shared immutable content intent for foreground and scheduled
  notifications;
- the 0.1.64 intent builder allowing exactly one opaque target extra while
  source hardening forbids raw resource fields in that payload;
- bounded native target resolution and result allowlisting;
- continued absence of public lock-screen visibility.

Exact-head PR run **43159936358** passed repository source/docs checks,
generated Android deep-link/privacy assertions, pinned Dart formatting,
`flutter analyze --fatal-infos`, **395 Flutter runtime tests**, and debug APK
compilation. These checks verify source/build integration; they do not replace
the physical-device notification-tap gates below.

## Remaining gates

Physical Android validation still needs to cover notification taps from a
secure lock screen, cold process start, warm foreground/background activity,
multiple taps, OEM notification behavior and operator channel overrides.

The original 0.1.55 milestone intentionally stopped at the generic Incidents
destination. VirtHelm 0.1.64 adds a bounded exact-current foreground incident
focus using only an opaque digest; see
[the 0.1.64 follow-up](109-implementation-notification-incident-targets.md).
Scheduled notification targets, direct automatic resource-page navigation,
richer causal/cross-resource correlation, optional relay delivery and
production critical-alert guarantees remain gated. Cross-mode notification
delivery deduplication is implemented by the 0.1.57 follow-up.
