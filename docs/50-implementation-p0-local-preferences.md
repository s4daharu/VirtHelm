# F11 implementation — local appearance, refresh, and display preferences

**Increment:** 2026-11-04 source-level F11 local settings. This document supplements the point-in-time repository audit in [49](49-whole-repository-audit-2026-11-04.md). It does not certify an Android release.

## Delivered behavior

- **Appearance:** Device theme (default), Light, or Dark. The selected value drives MaterialApp.themeMode and is restored before the connection screen is displayed.
- **Read refresh:** Manual only (default), every 30 seconds, every minute, or every two minutes. The timer is scoped to the foreground and an active authenticated gateway. It is canceled on background, profile change, active-profile deletion, or controller disposal; it restarts after a successful profile activation or foreground resume. A resume triggers the existing immediate read refresh. Timer invocations use the controller's coalesced read-only refresh path, not a mutation endpoint. An inventory/authentication error stops scheduled network refresh attempts until a manual or foreground-resume read succeeds.
- **Display:** Show node CPU/memory/uptime on Home (default), or omit the optional metric subtitle. Node identity and state remain visible; guest identity and operation-confirmation information never depend on this preference.
- **Storage and privacy:** Keys `ui_theme_v1`, `ui_refresh_v1`, and `ui_node_metrics_v1` use SharedPreferences as **non-secret, device-local, app-wide** settings. Malformed or unknown values fall back to the safe defaults. Writes are serialized with other local metadata operations. Settings never access or rewrite the encrypted token vault. There is no analytics or background polling service.

## Safety boundaries

The separate 4-second UPID **in-session** task observer remains unchanged and is not governed by the preference. Automatic refresh makes idempotent inventory/storage/task-list GETs only, respecting bounded GET retries and generation guards; it never submits power POSTs. A failed fetch may leave the previously displayed data stale, and no read failure authorizes a mutation. Changing display density does not change server polling, task reconciliation, or privileges.

Refresh is a foreground convenience, not a network watcher or persistent offline cache. Platform lifecycle/device interruption, Android process death, least-privilege PVE access, certificate security and performance at 200 guests still require instrumented verification.

## Source-level acceptance coverage

- Pure/controller tests: defaults, unexpected stored types, persistence without credential writes, reload, controller updates.
- Widget tests: persisted theme in MaterialApp and Settings controls; hiding node metrics leaves identity visible.
- Foreground timer regression: one selected interval triggers one read, background blocks periodic reads, foreground resumes and schedules another read; no mutation occurs.
- Repository CI is required on the **exact final branch SHA**: Python docs/source checks, pinned Dart formatter, analyzer, Flutter tests, and Android debug build. These are source gates, not real PVE 9.2/8.4 or physical Android certification.

## Remaining P0 / release scope

F09 task details/log explorer and F12 persistent cache/network-aware offline classification remain unimplemented. External PVE fixtures, physical Android validation, production-signing/recovery checks, dependency/license/security review and an independent release decision remain open. See [test gates](33-test-acceptance-release-gates.md).
