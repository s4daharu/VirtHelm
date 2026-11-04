# VirtHelm — P0 bounded idempotent GET retries

**Implemented in source:** 2026-11-04. **Scope:** F12 / CORE-05 read-retry increment for the Flutter Android PVE API-token gateway.

## Behavior

All gateway GETs (server version, inventory, storage, recent server tasks, guest preflight and UPID status) now receive at most **three total attempts**. After a transient failure the gateway waits before a retry: 200–299 ms, then 400–499 ms (exponential backoff with bounded jitter). No hidden background jobs or persistent request queue are added.

A retry is allowed only for connection, connection-timeout, send-timeout and receive-timeout failures, or HTTP 408, 429 and 5xx responses. The gateway **does not retry** HTTP 3xx redirects, 401/403, ordinary 4xx, TLS/certificate failures, malformed successful envelopes or unexpected local exceptions. Status and failure reporting still use the existing safe messages, without exposing response bodies or credentials.

**POSTs are never retried**, regardless of error type. A potentially executed guest operation retains its existing unknown-outcome semantics and must be reconciled through authoritative task/inventory reads before another mutation. Successful reads do not bypass the controller's fresh-inventory, profile-generation or guest-target guards.

The gateway is bound to one validated connection profile and credentials. Closing it during backoff prevents any subsequent delayed GET attempt. Jitter is local and does not transmit metadata outside the PVE host.

## Test coverage

The gateway regression suite checks successful recovery after HTTP 503 then receive timeout, exhausted connection timeouts (three requests/two waits), bounded delay ranges, no retries for 3xx/401/403/404, TLS or malformed success payloads, a single POST on HTTP 503 and cancellation of the pending retry when its profile gateway closes.

Normal delivery gates remain required for the final branch commit: docs/source checks, immutable Dart format, fatal-info analysis, Flutter unit/widget tests and Android debug APK build.

## Remaining limitations and release evidence

This increment adds simple bounded retries, **not** an operating-system connectivity observer or an offline queue. Error categories and UI messages are not yet fully differentiated for DNS, connect/read timeouts and offline transitions. Persistent offline read cache, rich task details/logs and user-configurable theme/refresh/display preferences remain separate P0 gaps.

The contract requires real PVE 9.2 and 8.4 regression fixtures, restricted ACL/TLS failure cases, device radio/VPN transitions and performance/request-count validation before any release-level compatibility claim. The source tests do not prove a live deployment works.
