# F09 follow-up — local recent-task search and status filters

**Increment:** 2026-11-05. This source-level, read-only task timeline enhancement follows [task log pages and refresh](55-implementation-f09-task-log-pages.md). The feature is **not** live PVE 8.4/9.2 or Android release certification.

## Scope

- Filter **already loaded** recent server tasks on the Tasks screen. Search is whitespace-trimmed and case-insensitive, matching operation codes and display labels, node, resource ID and UPID.
- Compose an exact node selector with the conservative displayed task state: **all, running, succeeded, failed or unknown**. A terminal `stopped` task without an explicit exit status is **unknown**, never inferred as successful or failed.
- Preserve the server task order (newest first as received), and retain the existing on-demand task-detail action. A clear "no matching tasks" message is distinct from "no tasks visible to this token" and from partial server read errors. This is not a task history API or persistent archive.
- The "This session" task list remains visible and unfiltered, so active/uncertain writes are never hidden by a server-task filter. Filtering does not trigger API requests, mutate tasks, affect locks, or retry POST requests.

## Local privacy and session isolation

- Search input and selectors live **only** in the Tasks tab widget, not preferences, secure storage, logs, telemetry, or controller state.
- A widget key tied to the exact profile ID **and connection generation** resets search and selectors on a profile switch or a reconnect to the same profile. Stale, partial, or permission-denied reads do not masquerade as filter results; previously existing read-error banners remain.
- No new API endpoints or permissions are required. HTTPS, certificate checks, origin binding, bounded GET retries and ambiguous mutation outcomes are unchanged.

## Verification boundary

Synthetic pure-Dart filter tests cover stable ordering, trimmed/case-insensitive search, node/operation/resource matching, conservative terminal-state semantics, combined filters and unmatched results. Widget regressions cover interactive search, state filtering and profile reset. Final branch checks must pass the pinned formatter, analyzer, Flutter tests, docs/Python source guards and debug Android APK build before merging. Live PVE contract/ACL fixtures, physical Android accessibility/performance and independent security review remain open.
