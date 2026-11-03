# Technical Architecture (Flutter/Dart, Android only)

## 1. System boundary
Flutter communicates **directly** to PVE `pveproxy` HTTPS API over LAN/VPN. There is **no app-owned server, shared credential vault or public cloud** in MVP. `pveproxy` exposes HTTPS port 8006 and can forward requests to other cluster nodes. Multiple independent cluster profiles are local to the device. This is not a Proxmox Datacenter Manager API client.

## 2. Layering
```text
presentation: screens + widgets <- view models / Riverpod providers
              ^
application:  operations: ConnectProfile, LoadInventory, GuestPowerAction, TrackTask
              ^
domain:       typed immutable entities; repositories interfaces; errors; permissions
              ^
data:         PveApiClient, PveAuthStrategy, PveRepository, secure storage,
              settings storage, volatile non-sensitive cache, JSON codecs
```
Follow Flutter's strongly recommended separation of views/viewmodels/repositories/services. For MVP use MVVM + Riverpod as a **project choice**, `go_router` for navigation, `dio` for HTTP, `flutter_secure_storage` for secrets, `shared_preferences` for non-sensitive settings. There is no obligation to add `freezed`, `retrofit`, `drift` or `build_runner` until they reduce demonstrable boilerplate. Use `pubspec.lock` and review plugin licenses/security.

## 3. Folder structure after `flutter create --platforms=android app`
```text
app/
  android/                 # ONLY generated platform runner
  lib/
    main.dart
    app/app.dart
    app/router.dart
    core/network/pve_http_client.dart
    core/network/api_error_mapper.dart
    core/security/credential_store.dart
    core/security/tls_trust_policy.dart
    core/storage/settings_store.dart
    domain/models/{cluster_profile,node,guest,task,storage}.dart
    domain/repositories/{inventory_repository,guest_repository,task_repository}.dart
    data/pve/{pve_api,pve_auth,serializers}.dart
    data/repositories/{inventory_repository_impl,...}.dart
    features/connections/{data,viewmodels,views}/
    features/overview/{viewmodels,views}/
    features/guests/{viewmodels,views}/
    features/tasks/{viewmodels,views}/
    features/settings/{viewmodels,views}/
  test/{unit,widget,fixtures}/
  integration_test/
  pubspec.yaml
  pubspec.lock
```

## 4. Network contract
- Base URL: `https://<host>:8006/api2/json` (allow explicit HTTPS port and reverse-proxy prefix only with separately tested support; no HTTP). Normalize input without stripping arbitrary path on user reverse proxy.
- Normalize `ApiEnvelope<T> { data: T }`; parse error responses with status code, API message and field errors, never trust any field to be present in all versions.
- Apply authentication **per profile** via typed `AuthStrategy` (`ApiTokenAuth`, later `TicketAuth`), not global interceptor state shared between profiles.
- Cap concurrent status calls (e.g. 4) and use bounded connect/read timeouts (e.g. 10s/30s configurable). The proposed values need field measurement.
- Treat `UPID` as opaque server task identifier; URL encode by path segment. `GuestKey` includes cluster profile + guest type + node + VMID.
- On profile switch, invalidate old requests and screen state; cancel in-flight operations; prevent post-switch mutation from a retained callback.
- Read polling: foreground only, preferably 15–30 seconds with user override and exponential backoff; pause on Android background and connectivity failure.
- Non-idempotent writes are **never automatically retried** after ambiguous timeout; investigate task history / guest status first.

## 5. Caching/state model
Repository serves `ResourceSnapshot<T> { value, fetchedAt, source, stale, profileId }`. Non-sensitive summaries may be cached for last-known display. No persisted API tickets, passwords or token secrets in normal preferences, SQLite or JSON test fixtures. Redact raw upstream error body before UI/log output.

## 6. Operational observations
PVE API reads may return incomplete results depending on ACL. `cluster/resources` is convenient for global overview but is not guaranteed to enumerate inaccessible resources. Node details may need separate node-specific calls. Task outcomes are asynchronous. Advanced features may have version-specific endpoint parameter variation: verify with the API viewer **for each supported version** and integration tests.

## 7. Scalability decisions
Target 200 guests as a performance fixture, page or virtualize lists, avoid one API request per row on each scroll, deduplicate duplicate profile requests, prevent polling when view not active, and don't maintain a persistent WebSocket for mere status polling. Tests must ensure 401/403, 500, 596, invalid JSON, empty data and cancellation yield deterministic UI states.
