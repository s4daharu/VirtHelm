# API Errors, Offline Handling, Concurrency and Task State

## Structured error taxonomy
`NetworkOffline`, `DnsFailure`, `ConnectTimeout`, `ReadTimeout`, `TlsUntrusted`, `TlsNameMismatch`, `AuthenticationExpiredOrInvalid` (401), `PermissionDenied` (403), `NotFoundOrMoved` (404), `ConflictOrLocked`, `ValidationError` (4xx), `ServerError` (5xx), `MalformedResponse`, `UnsupportedFeature`, `TaskFailed`, `TaskUnknown`, `Cancelled`.

Not every PVE response is a conventional HTTP code; map safely from HTTP status, API envelope and documented PVE error text. Don't render upstream raw HTML. Avoid assuming 404 means missing guest when permission filters, migration or node selection may differ.

## Retry policy
| Operation | Automatic retry? | Policy |
|---|---|---|
| GET version/list/status | Yes, bounded | backoff with jitter, network aware, cap attempts |
| GET task status | Yes, bounded until TTL | poll at e.g. 2s then 5s; stop on terminal, cancel, session expiry |
| POST guest lifecycle | **No** | unknown outcome on timeout, verify state/history before offering resend |
| Ticket renewal/login | No blind loop | explicit session state with user interaction for MFA |
| TLS/cert mismatch | **Never** | refuse connection; guided trust remediation |

## State machines
Connection: `unconfigured -> checkingTLS -> validatingAuth -> ready | partialAccess | offline | failed`. Switching profile cancels requests and clears scope-specific screen data.

Mutation: `confirming -> submitting -> taskPending(UPID) -> taskSucceeded | taskFailed | outcomeUnknown`. Do not use an optimistic “VM is running” update as the sole indicator; reconcile authoritative state after task completion.

## Offline policy
Cache non-sensitive summaries optionally, with timestamp and cluster ID. Surface stale chips and disable mutations. Cache deletes on profile deletion, auth revocation, or sign out. No background polling worker or notification service in MVP; Android battery/doze constraints are not circumvented. Manual refresh remains available.

## Instrumentation
Log coarse timings, anonymized identifiers where possible and error class **without** Authorization, cookies, response bodies, task log lines, hostnames or guest names by default. Diagnostics require explicit opt-in and preview/redaction.
