# UI overhaul foundation — shared Material 3 components and screen polish

This note records the first implementation slice of the UI overhaul. It is a source-level change with synthetic widget coverage only; it is **not** physical Android, TalkBack, performance, live PVE compatibility or release evidence.

## Scope

- A shared design foundation in `app/lib/ui/theme.dart`: semantic status colors, tabular numeric display styles, component themes for cards, chips, inputs, navigation, dialogs-adjacent surfaces, snackbars and progress indicators.
- A shared component library in `app/lib/ui/components.dart`: section headings, message cards, metric bars, usage bars, normalized chart samples and one accessible sparkline card.
- `StatusChip` now pairs every status label with an icon, semantic color and a TalkBack label. Positive, warning, error and neutral states are mapped explicitly; status is never conveyed by color alone.
- `EmptyState` supports an optional recovery action so empty, offline and permission states can offer a safe next step.
- Home adds a foreground incident summary card and keeps freshness visible in the app bar. The summary is read-only and links to the existing Incidents tab.
- Guest, node and storage detail routes now support pull-to-refresh and use the shared metric/chart components. The explicit “Load history” action remains; timeframe selection still performs no request.
- Task details render status as a badge and task log lines in a bounded monospace card. Logs remain on-demand, ephemeral and non-exportable.
- Settings reports the display version from `app/lib/core/app_info.dart`; `check_source.py` enforces that it matches `app/pubspec.yaml`, replacing the stale hardcoded `0.1.3` label.

## Rebuild boundary

`MaterialApp` is no longer rebuilt on every `AppController` notification. A small theme notifier rebuilds the app only when the persisted theme preference changes; inventory, task and incident updates rebuild the active shell subtree. This is a first step toward the 200-guest rebuild target in [the Android experience plan](31-android-native-premium-experience.md).

## Safety boundaries preserved

- No API endpoint, credential, persistence or mutation behavior is added.
- Guest action cards, confirmation dialogs, freshness guards, single-flight and unknown-outcome lockout behavior are unchanged.
- Task logs remain bounded, on-demand and non-persistent.
- Stale, offline, partial-permission and task-coverage warnings remain visible.
- The incognito/TLS exception policy and profile-local certificate bypass are unchanged.

## Verification

- `flutter analyze --fatal-infos` passes.
- Existing widget/controller regressions pass locally under the available Flutter SDK, including the 320dp/200% text-scale shell test after the new incident summary was accommodated.
- New component tests cover icon/status/semantic-label pairing and the optional empty-state action.
- Physical Android TalkBack, 200% text, contrast, 360/393/412dp screenshots and performance benchmarks remain open.
- Live PVE 9.2/8.4 fixtures are not affected by this presentation-only slice.

## Remaining overhaul work

The screen-level restructuring described in [the UX navigation plan](03-ux-navigation.md) and [the premium information architecture](23-premium-ux-information-architecture.md) is intentionally not complete. Guest detail tabs and sticky actions, guest-filter consolidation, a tasks timeline, a full-screen threshold-rule editor, connection management and About surfaces, chart axes/tables, app lock and notification surfaces remain future work.
