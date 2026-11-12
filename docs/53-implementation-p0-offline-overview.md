# F12 implementation — opt-in, counts-only offline overview

**Increment:** 2026-11-05. This is a bounded source-level part of F12/CORE-04, building on [typed transport errors](52-implementation-p0-transport-errors.md) and the [retry policy](48-implementation-p0-read-retries.md). This is not release certification or a claim of full offline-mode completion.

## Behavior and privacy

- The operator explicitly enables **Keep offline overview counts** in Settings for the active connection. It is **off by default**, stored separately for each profile.
- A fully authenticated, clean live inventory read saves just seven versioned integer fields: schema version, time, total/online nodes, total/running/stopped guests. A cache record contains **no hostnames, addresses, node names, VMIDs, guest names, per-resource metrics, task logs, raw API payloads or credentials**.
- When a live inventory is absent and a typed transport failure occurs, Home may display those counts with the visible **CACHED COUNTS / not live** label, original timestamp and explicit warning. Guest lists, node identity, storage details, task logs and all actions still require live reads.
- Records are keyed to the local profile ID and eligible only for seven days. Bad versions, unexpected fields/types, inconsistent counts, oversized payloads, future timestamps and expired data are ignored rather than interpreted as live data. An offline record is never converted into a live `Inventory`.
- Opt-out, profile deletion, profile editing/credential replacement, and observed 401 authentication failure clear the stored record. The app does not replicate it to a cloud service; Android app backups remain disabled. Cache write failures never change live authorization.

## Write and session safety

Cache persistence uses the repository's serialized local-write path and checks that consent and the profile still exist. Live refreshes only write summaries after the foreground inventory and supplemental read phase has finished without an authentication error. Generation checks prevent UI results from a previous connection session. Failure to reach a server does **not** infer that Android is offline, and the existing exact-target fresh-inventory/live-preflight/UPID guards and single-shot POST policy remain intact.

## Verification and remaining work

Synthetic tests cover opt-in/default-off behavior, count-only serialization, invalid/expired/future/corrupt record rejection, profile isolation and deletion, credential-edit invalidation, cache display on cold transport failure, revocation behavior, and no mutation from cached summaries. Final source gating: Python docs/source tests, immutable formatter, fatal-info analyzer, full Flutter tests and Android debug build on the exact PR SHA.

**Follow-ups:** Android default-network observation and conservative offline/recovery handling are documented in [docs/54](54-implementation-p0-android-connectivity.md). AND-011 adds a separately opted-in, 24-hour bounded stale inventory list in [docs/102](102-implementation-offline-stale-inventory.md); the original counts-only cache remains independent and lower-data. **Still open:** persistent node/guest detail, metrics/config/storage/task caching, PVE 9.2/8.4 version/ACL fixtures, physical Android security/process-death/radio/VPN tests, and external release approval. Every cached observation represents what the token saw at an earlier successful read, **not** a certified live or full cluster inventory.
