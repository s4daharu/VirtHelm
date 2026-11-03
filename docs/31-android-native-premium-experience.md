# Native Android Experience, Offline and Performance Plan
Only Android **mobile phones** are targeted; no tablet/web/iOS/macOS/Windows/Linux runners. Treat foldable phones as narrow/expanded phone experiences; verify rotation without inventing a tablet product.

## Android experience backlog
- App icon and adaptive monochrome themed icon, branded launch screen, curated splash/lock screen.
- Material 3 dynamic color option and brand palette, dark/light/AMOLED dark mode, high-contrast mode.
- Biometric app unlock with Keystore binding and device credential fallback; short auto-lock timeout after background.
- Android home screen widgets: non-secret stale-aware site health and guest status; tap opens app then unlock. Mutations disabled from widgets by default.
- Notifications for opted-in task completion/failed tasks and alert rules; Android 13+ runtime permission, channels, lock screen privacy.
- Quick access shortcuts and search deep links **only** to view pages; always validate profile ID and require unlock, no privileged actions from external intents.
- Intent-sharing and redacted diagnostics: user-initiated export of summary, logs and task IDs scrubbed of identities/secrets as configured.
- Android clipboard: copy non-secret addresses only with explicit tap; never silently copy tokens/console tickets.
- Offline read-only viewing; stale banners with exact time; no queued offline administrative commands.
- Optional accessibility enhancements: TalkBack semantic charts, spoken status, haptics, large font, reduced motion.
- Optional localized UI with date/time, RTL, units, large number grouping; translations reviewed and never mutate server machine IDs.

## System integration constraints
Android 13+ non-exempt notifications require POST_NOTIFICATIONS permission. Android periodic WorkManager **minimum 15-minute interval, inexact**; VPN and battery optimization can defer work. Android 15 edge-to-edge behavior requires proper insets for target API 35+ (actual Play target version checked at shipment). Alarm/foreground service should not be used to imply reliable server monitoring without compliant reason.

## Rendering and performance budgets (proposed, not achieved)
- 60fps goal for normal screens on midrange reference phone.
- Cached home first meaningful paint <=1.5 seconds measured in release/profile benchmark; fresh remote network response separate.
- 200 guests searchable with virtualization, no global widget rebuild waterfall.
- Avoid heavy graph calculations on UI isolate; parse large payloads in isolate if profiling proves needed.
- Alert and poll scheduler must cap requests, persist data age, back off on failure and pause invisible pages.
- Avoid background battery drain; compare idle battery over 24h with baseline device and VPN.
- Offline cache data retention configurable and profile-specific; default minimize or avoid disk persistence for sensitive guest names.

## Accessibility acceptance
TalkBack can navigate every action, high-risk confirmation reads target and consequences, charts have tabular alternatives and understandable date ranges, 200% text scale has no clipped confirmation, controls >=48dp, color contrast meets applicable guidance, landscape console keyboard not obscured by IME.

## Native testing matrix
Phones Android API 26, 29, 33, 35 and latest available; 360dp small screen, 393dp average, 412dp large, gesture and three-button navigation; biometric availability/unavailable; Wi-Fi -> cellular with VPN; doze/standby; process death, restore, low RAM, notification denial; font scaling and TalkBack. Each release must verify current OS and Google Play policies, not hardcode 2026 policy assumptions.

## Sources
https://developer.android.com/develop/background-work/background-tasks/persistent/getting-started/define-work
https://developer.android.com/develop/ui/compose/notifications/notification-permission
https://developer.android.com/develop/ui/views/layout/edge-to-edge
https://docs.flutter.dev/perf
