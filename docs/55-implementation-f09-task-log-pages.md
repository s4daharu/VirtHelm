# F09 follow-up — bounded task-log pages and manual status refresh

**Increment:** 2026-11-05. Source-level, read-only feature work following [F09 task details](51-implementation-p0-task-details.md). **Not** evidence of live PVE 9.2/8.4 compatibility, physical Android validation, or release certification.

## User behavior

- Opening a known task requests fresh status and log page 1 (`start=0&limit=100`) as before. A **Refresh status and log** control explicitly re-requests the currently selected page and status, with no automatic polling.
- A full page offers **Next 100**. Subsequent pages use bounded `start` offsets 100, 200, 300, and 400. **Previous 100** re-fetches the previous page. At most **500** lines may be inspected per visit; the screen shows only one page at a time, and the server may return fewer than 100 lines.
- The gateway validates `start` as a 100-line aligned integer from 0 to 400 **before** network I/O. Requests are GET-only, preserving existing bounded transient retry rules and 401/403/TLS handling.
- The page only offers **Next 100** when the response filled all 100 slots, counting malformed rows so malformed neighbors do not hide valid ones. All log strings remain capped to 500 characters; malformed rows are skipped and counted. The task status is independently updated on each page or refresh. No task action, elevated privilege, or automatic write retry is introduced.

## Session privacy and safety

- Both status and log reads require an exact currently known task UPID/node, current profile ID, and connection generation before and after asynchronous requests. A profile switch or reconnect redacts the route; stale results cannot render or authorize writes.
- Sensitive log lines exist only in the open details route's ephemeral widget state. Changing pages replaces the prior page; they are never persisted, exported, uploaded, inserted into app-controller state, or used in metrics/telemetry.
- This is a deliberately bounded preview, **not** a full searchable F17 task explorer. Unknown task outcomes remain unknown and existing guest mutation locks are unchanged.

## Verification boundary

Synthetic gateway tests assert GET path, offset and page-size enforcement before network requests. Controller and widget tests cover explicit page navigation, refresh, retained zero POST calls, and redaction after a profile switch. Final CI must pass immutable Dart formatting, analyzer, Flutter tests, generated Android hardening, docs/source checks, and debug APK build on the **exact PR head**. Live PVE task-log response fixtures, ACL matrices and physical Android security/accessibility testing are still open.
