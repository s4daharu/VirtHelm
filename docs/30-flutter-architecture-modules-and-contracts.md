# Flutter/Dart Engineering Blueprint — Modules and Contracts
Android phones only. Flutter + Dart; modular feature-first MVVM with Riverpod for state, go_router navigation, Dio HTTP, Android Keystore-backed secure storage. **Package choices and versions are provisional until build/test and license audit.**

## Repository shape
```text
app/
  android/                          # only generated platform runner
  lib/
    main.dart
    app/{router,theme,feature_flags,providers}.dart
    core/
      auth/{auth_strategy,session_store,capability}.dart
      network/{http_client,origin_guard,error_mapper}.dart
      security/{trust_store,credential_store,app_lock}.dart
      operations/{operation_orchestrator,preflight,task_tracker}.dart
      data/{cache,refresh_policy,telemetry_local}.dart
      ui/{atoms,layout,charts,states}.dart
    domain/
      entities/{cluster,node,guest,task,storage,alert,backup,identity}.dart
      repositories/...
      usecases/...
    integrations/{pve,pbs,pdm,relay}/
    features/{onboarding,home,explore,guests,console,tasks,alerts,
              backups,infrastructure,insights,settings}/
    l10n/
  test/{unit,widget,fixtures,golden,security}/
  integration_test/
  tool/
docs/
```

## Architecture contracts
- UI widgets are passive and do not directly issue HTTP. ViewModels orchestrate user intent -> domain use cases -> repositories -> typed backend adapter.
- One `BackendAdapter⟧ per PVE/PBS/PDM product with version detection and supported capability manifest, no generic “send arbitrary API endpoint” UI.
- `PveHttpClient⟧ owns base origin and scoped AuthStrategy, TLS policy, timeouts, JSON envelope, retry semantics, rate cap and redaction; no global token interceptor across profiles.
- `OperationOrchestrator⟧ validates immutable identity, capability, freshness, authorization hint and impact, creates local op ID, calls specific typed POST once, tracks UPID, and classifies terminal result.
- `CacheRepository⟧ never stores auth/cookies; all values tagged profileId + fetchedAt + source + stale and purged on profile deletion.
- `AlertEngine⟧ consumes versioned sample series with missing-data semantics, separate from request scheduling.
- `FeatureRegistry⟧ centralizes min supported server feature/version, auth, risk, dependencies and visible UI copy. Version support is proved by tests, not guessed.
- Android platform channels limited to Keystore, biometrics, secure-screen, notification and optional widgets; must be unit-integration tested on devices.

## Suggested typed models
```text
BackendIdentity { backendKind, profileId, verifiedOrigin, serverVersion }
ResourceKey { backendKind, profileId, node?, resourceKind, serverId }
MetricPoint { observedAtUTC, value?, unit, source, quality }
ReadSnapshot<T> { profileId, value?, fetchedAtUTC, isStale, completeness, error? }
Capability { featureId, supported, allowedHint, reason?, evidenceVersion }
MutationRequest { opId, target:ResourceKey, preflightHash, params, risk }
MutationResult { opId, submittedUPID?, state, lastKnownServerState?, evidence }
Alert { ruleId, profileId, observedAtUTC, state, severity, reason }
```

## HTTP and asynchronous semantics
GET may use retries with bounded exponential backoff + jitter, conditional if safe and proven; never automatic retries on POST/PUT/DELETE after ambiguous timeouts. Handle PVE `{ "data": ... }⟧ envelope explicitly. URL path components encoded by segment. UPID is opaque, never split unless justified by PVE spec. Concurrency 4 reads/proxy initially **proposed and benchmarked**, bounded API 429/5xx handling. Foreground state cancel via provider generation; task observer may resume after process death by polling persisted non-secret UPID only.

## Lifecycle
On foreground: unlock -> profile -> resolve trust -> refresh capabilities/inventory -> render cached then verified data -> poll visible section. On background: stop console and foreground polls, revoke live volatile session when app lock demands, prevent widgets from fetching without explicit consent. On profile change: increment generation; old callbacks ignored and requests canceled, old profile data never reaches new UI.

## Unit and library choices to evaluate
| Concern | Candidate | Required decision |
|---|---|---|
| State | flutter_riverpod | version pin, provider test harness |
| Networking | dio | cookie handling, redirect stripping, timeout semantics |
| Navigation | go_router | guarded redirects and deep link validation |
| Models | hand-typed initially; freezed/json_serializable later | codegen maintenance vs error risk |
| Storage | flutter_secure_storage + limited shared_preferences | backup exclusions, Android API requirements |
| Graphs | maintained Flutter chart library | license, a11y, axis/time precision |
| Local DB | drift/sqlite only when needed | encrypt sensitive metadata or keep cache ephemeral |
| Background | WorkManager Android adapter only if approved | OS scheduling and VPN reliability |
| Charts/console | noVNC or maintained VNC + WebView after spike | license, security and physical keyboard testing |

## Tests at module boundaries
Contract fixtures for PVE 8.4 and 9.2, PBS 4.2, PDM 1.1; property tests for unit conversion and CPU rate; operation state-machine fault injection; no cross-profile leakage; golden screens at 360–412dp in dark/light; fuzz malformed API fields; device tests Android 8–current supported. Record exact Flutter/Dart/toolchain versions in lockfile/release evidence.
