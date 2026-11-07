# Node and storage detail tabs

This note records the node/storage detail alignment with the guest-detail tab pattern. It is source-level synthetic coverage only; it is not physical Android, TalkBack, performance, live PVE or release evidence.

## Structure

- **Node detail** now has two tabs:
  - **Overview** — node identity, freshness/staleness, current CPU/memory meters and uptime.
  - **Metrics** — the existing explicit node RRD history loader, timeframe chips, sample count and CPU/memory sparkline cards.
- **Storage detail** now has two tabs:
  - **Overview** — storage identity, shared/content metadata, capacity usage bar, freshness and stale/offline copy.
  - **Capacity** — the existing explicit storage RRD capacity history loader and usage chart.

Both routes keep their app-bar refresh action and pull-to-refresh on each tab. Tab keys are stable for widget tests and accessibility automation.

## Safety boundaries

- Read-only. No node or storage mutation is introduced.
- RRD history remains explicit, GET-only, bounded, transient and profile/generation scoped.
- Timeframe selection alone still performs no request.
- Stale/offline, missing-resource and session-change redaction behavior is preserved.
- No API, credential, persistence or retry behavior is changed.

## Verification

- `flutter analyze --fatal-infos` passes.
- The full Flutter suite passes locally: 161 tests.
- Node and storage history regressions were updated to select the metrics/capacity tab explicitly and still verify request timing, summaries, sample counts and profile-switch redaction.
- Physical Android TalkBack, touch-target, 360/393/412dp screenshots and performance benchmarks remain open.

## Remaining work

Guest-list filter consolidation, task timeline virtualization, a full-screen threshold-rule editor with searchable grouped targets, dedicated connection management, AMOLED/high-contrast themes, app lock/biometrics, notifications and golden screenshots remain future work.
