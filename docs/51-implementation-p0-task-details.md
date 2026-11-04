# F09 implementation — on-demand task details and bounded log view

**Increment:** 2026-11-05 source-level F09 read-only task inspection. This supplements the historical [whole-repository audit](49-whole-repository-audit-2026-11-04.md) and [F11 implementation](50-implementation-p0-local-preferences.md). This is **not** live PVE validation or release certification.

## Behavior

- Both in-session tracked UPIDs and recent node server-history UPIDs have a **View details** action.
- The details screen requests a fresh `GET /nodes/{node}/tasks/{upid}/status` and separately fetches a bounded first page (`start=0&limit=100`) of `GET /nodes/{node}/tasks/{upid}/log`. Both remain ordinary idempotent reads under the existing bounded GET retry policy. There is no POST from this screen, task retry, or inferred operation success.
- The status uses the existing conservative state machine: only `stopped` with `exitstatus=OK` means succeeded; absent exit status is unknown. Permission denied (403), invalid response, expired auth (401) and unavailable log/status are shown separately. A 401 on status avoids a second log fetch.
- Log records decode `n` and `t` fields, preserve valid rows alongside malformed entries, sort by row number and bound returned rows to 100 and displayed text to 500 characters per entry. This is a deliberate bounded first-page preview rather than the full P1/F17 searchable log explorer.

## Privacy and lifecycle

Task logs can contain sensitive server output. The screen warns of this before showing lines; VirtHelm does **not** persist, upload, report, export, or instrument task-log bodies. No PVE tokens are saved with task logs. The read is initiated **only** when a user opens a known task, and does not change operation locks or request elevated privilege.

Controller lookup requires the currently displayed profile ID, same connection-generation token, and a UPID/node matching one of the current session or server-history task records. Both API awaits re-check connection generation, so a slow request cannot expose a previous connection's results after a switch. The screen redacts its cached FutureBuilder result as soon as the profile/session changes.

## Verification and boundaries

Regression tests cover malformed/long log rows, method/encoding/page bounds, non-retryable 403, independent status/log errors, no POST, late-result invalidation and UI redaction. Repository CI must pass on the **exact final branch SHA**: docs/source/Python tests, Dart formatting, Flutter analysis/tests and Android debug build. Real PVE 9.2/8.4 task log fixtures, permission matrices, physical Android tests and independent security review remain open. F12 persistent offline cache and complete network-aware state classification are still unimplemented.
