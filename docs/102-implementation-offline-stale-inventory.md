# AND-011 offline stale-aware inventory — bounded implementation (0.1.56)

## Milestone

VirtHelm now supports an explicitly opted-in, profile-scoped stale inventory
list for short offline/transport-failure browsing. It builds on the earlier
counts-only offline overview without changing that safer, lower-data option.

The detailed cache is **off by default** and is a separate setting named
**Keep offline inventory list**. Enabling counts-only caching does not enable
this inventory cache.

## Stored data boundary

A successful clean live inventory may persist only:

- snapshot timestamp;
- node name and last-observed node status;
- guest name, VMID, QEMU/LXC type, node, last-observed status and template
  marker.

The cache deliberately excludes:

- node/guest CPU, RAM, disk, uptime and I/O metrics;
- tags and pools;
- storage inventory or capacity;
- guest configuration, snapshots, backups and permissions;
- task history, UPIDs and logs;
- profile endpoints and credentials;
- raw PVE responses or arbitrary future fields.

Records are schema-versioned and validated before storage and on read. Node and
guest identity strings are bounded and control characters are rejected.
Duplicate node names or VMIDs are rejected. The cache is bounded to 256 nodes,
5,000 guest rows and 512 KiB serialized data. A stale inventory expires after
24 hours. Future timestamps, unknown versions, extra fields, malformed rows,
oversized data and expired data are not displayed.

If a clean live inventory cannot be converted into this bounded shape, VirtHelm
clears any older detailed inventory instead of retaining an obsolete list.

## Display-only safety

Cached data is never converted back into the live `Inventory` model.

Home may show cached node/workload cards and aggregate counts, but every cached
card is non-interactive and visibly labeled **CACHED / NOT LIVE**. Cached node
metrics are unavailable.

The Guests destination uses a dedicated stale browser when there is no live
inventory. It supports only local search over cached guest name, VMID, node and
type. It intentionally omits live-only affordances including:

- guest detail navigation;
- node detail navigation;
- favorites;
- saved-view editing;
- status/type/tag/pool filter controls;
- VM/container creation;
- configuration, metrics, snapshots, backups or permissions;
- task-detail reads;
- every guest or infrastructure mutation.

A stale cache never makes `isInventoryFresh` or `isInventoryWriteSafe` true.
All existing mutation and detail-read paths continue to require the current
live session/generation and live inventory objects.

## Consent, lifecycle and erasure

Detailed cache consent is stored separately for each connection profile.

The detailed cache is purged when:

- the operator disables **Keep offline inventory list**;
- a profile is edited or its credential/ACL identity is replaced;
- the profile is deleted;
- an authenticated read reports HTTP 401.

The cache may be loaded only after Android reports no default network or when a
connection/refresh fails with a typed transport failure and there is no live
inventory. Android network presence is still only a hint; it is not interpreted
as proof that PVE is reachable.

Successful live refresh replaces the stale display with live inventory.
Android application backups remain disabled, so these local stale identities
are not included in normal Android backup transport.

## Verification

Automated coverage includes:

- allowlist-only serialization and exclusion of metrics/tags/pools;
- 24-hour expiry and future timestamp rejection;
- unknown schema/extra field/invalid identity/duplicate VMID rejection;
- default-off and profile-scoped repository consent;
- purge on opt-out, edit and profile deletion;
- controller save/erase behavior from a clean live snapshot;
- cached Home node/workload rendering with no tap handlers;
- dedicated Guests stale browser with search and no live creation controls;
- separate Settings opt-in.

Repository source checks additionally enforce the 24-hour cap, separate setting
key, non-interactive stale UI markers, authentication-loss purge wiring and the
absence of any `Inventory.fromResources` reconstruction in the offline cache
implementation.

Pinned formatting, analyzer, Flutter runtime tests and debug APK compilation
remain the merge gates. Physical-device process-death, radio/VPN transition and
storage inspection remain release-validation work.

## Remaining scope

This milestone is intentionally not a general offline mode. It does not cache
node/guest detail pages, metrics, storage, configuration, snapshots, backups,
permissions, tasks or incident evidence.

Broader offline detail caching requires a separate privacy/security decision.
PVE 8.4/9.2 ACL fixtures, physical Android security/process-death/radio/VPN
validation, production signing and independent release/security review remain
open.
