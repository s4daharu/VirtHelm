# F12 implementation — safe transport-failure classification

**Increment:** 2026-11-05 source-level F12 / CORE-05 error-state follow-up. This builds on the [bounded GET retry implementation](48-implementation-p0-read-retries.md). This is not an Android networking test, live PVE integration test, or release certification.

## Delivered behavior

The PVE gateway returns a typed, optional `PveTransportFailure` classification on `PveFailure`, alongside its existing safe user-facing error message:

- `dnsFailure`: known hostname-lookup socket failures, using explicit lookup failure signals only.
- `networkUnreachable`: known unreachable network/host routes, **not** proof that Android is globally offline.
- `connectTimeout`: a connection was not established before the timeout.
- `responseTimeout`: request send or server response timed out.
- `connectionLost`: other connection-level failures that are not safely distinguishable.

Typed Dio timeout and SocketException evidence drives classification. HTTP responses (including 401, 403, 408, 429 and 5xx), TLS exceptions and certificate failures are **not** mislabeled as transport errors. Unrecognized transport errors retain generic guidance. Messages never interpolate hostnames, addresses, raw OS error details, response bodies or credentials. The existing Home error and stale-snapshot presentation consumes these safe messages, without displaying sensitive transport detail.

## Safety invariants

The existing three-total-attempt GET retry limit and jittered backoff remain unchanged. TLS validation, exact-origin certificate override policy, auth and permission handling, and redirect blocking are unchanged. A classification **does not authorize** guest mutation or replay an action: POST remains single-shot, and ambiguous connection/timeout outcomes still set `mayHaveExecuted` and require authoritative task-history reconciliation. No persistent socket telemetry or external diagnostics are introduced.

## Tests and remaining work

Synthetic gateway regressions exercise distinct network/DNS/timeout classes (including a SocketException wrapped as a Dio unknown error), redaction of raw socket details, and an uncertain single-shot POST on network loss. Final-source verification requires the exact-head documentation/source/Python checks, Dart format, analyzer, Flutter tests, and Android debug build.

**Still open:** an Android connectivity observer and automatic online/offline state transitions, a profile-scoped bounded and privacy-reviewed persistent read cache, real Wi-Fi/mobile/VPN/airplane-mode fault injection, and PVE 9.2/8.4 ACL/response fixtures. An unreachable server route must not be presented as definitive device-offline status. The F12 P0 requirement and external release gates are **not yet closed**.
