# BKP-002 Partial: Exact-Guest Backup Archive Visibility

**Date:** 2026-11-11  
**Version:** 0.1.43  
**Milestone:** M4 recovery operations / BKP-002 partial

## Scope delivered

VirtHelm now provides an on-demand, read-only backup archive list for one exact QEMU/LXC guest and one operator-visible backup storage from the guest Recovery tab.

This closes the most important truth gap left by the one-off backup-start milestone: a successful `vzdump` task is no longer the strongest evidence the UI can show. The operator can separately ask PVE whether matching backup content is currently visible on the selected storage.

Archive visibility is still **not** archive integrity verification and is **not** a restore test.

## Read contract

The bounded request is:

- `GET /nodes/{node}/storage/{storage}/content`
- `content=backup`
- `vmid={exact guest VMID}`

Proxmox documents storage content listing by VMID and identifies `backup` as the vzdump backup content type. VirtHelm already used the same storage-content endpoint family for LXC template discovery; this milestone adds a separate exact-guest backup parser and UI surface.

The response is capped locally at 500 rows. Only reviewed metadata is retained:

- volume ID;
- storage ID;
- exact QEMU/LXC type and VMID derived from the volume ID;
- creation time when reported;
- byte size when non-negative;
- format when short/control-character-free;
- the PVE `protected` flag when reported.

Notes, comments, arbitrary backend metadata, unknown future fields and archive contents are not copied into the display model.

## Exact guest identity

The API query is VMID-scoped, but VirtHelm does not trust VMID alone because VMIDs can be reused over time.

Each returned volume ID must also identify the current guest type:

- file-style `vzdump-qemu-{vmid}-...` or `vzdump-lxc-{vmid}-...`;
- PBS-style `backup/vm/{vmid}/...` or `backup/ct/{vmid}/...`.

Rows that do not match the exact current QEMU/LXC type and VMID, or cannot be safely parsed, are ignored and counted as unusable. Matching archives are sorted newest-first.

## Session and storage safety

Before issuing the GET, the controller requires:

1. the originating profile ID and connection generation to still be current;
2. Android default-network state not to be explicitly unavailable;
3. exactly one current guest matching node/type/VMID;
4. exactly one current storage matching the selected storage ID on that guest node;
5. that storage to still be enabled, active and advertise `backup` content.

The same guest and storage conditions are rechecked after the response. If either disappears or changes session, the result is discarded. A storage-content 401 invalidates authenticated live state through the existing read-loss path; other authorization failures remain server-authoritative and are shown as read errors.

No mutation permission is inferred from archive visibility.

## Recovery UI

Recovery now separates three distinct evidence classes:

1. guest snapshots;
2. currently visible backup archives;
3. recent `vzdump` task outcomes.

The archive section requires an explicit storage choice when more than one backup-capable storage is visible, performs no automatic background reads, labels the newest matching entry, and hides loaded data immediately when the exact guest/session/storage no longer matches.

After a new backup is submitted, any loaded archive list is invalidated so an older result cannot appear to prove the newly submitted backup exists.

## Truth boundary

This milestone deliberately does **not**:

- checksum or open an archive;
- consume PBS verification state;
- test restore;
- claim recoverability;
- delete or prune archives;
- change backup retention or schedules;
- expose restore mutations.

A visible archive proves only that the PVE storage-content read currently reports a matching backup volume for the selected guest/storage.

## Automated coverage

Synthetic regressions cover:

- exact GET method/path and `content=backup` + VMID query;
- file-style QEMU archive identity;
- PBS-style QEMU and LXC archive identity;
- rejection/ignoring of wrong guest type, wrong VMID and malformed neighboring rows;
- newest-first ordering and reviewed metadata;
- invalid storage rejection before I/O;
- controller exact-guest/exact-storage/session gating;
- Recovery UI on-demand loading, latest-archive presentation and redaction when the guest disappears;
- source-smoke guards for the model/gateway/controller/UI/document contract.

## Remaining validation gates

Disposable PVE 8.4 and 9.2 fixtures remain required for directory, NFS/CIFS and PBS-backed storage content schemas, restricted-token ACL behavior, QEMU/LXC volume-ID variants, deleted/reused VMIDs, protected backups, missing timestamps/sizes, large result sets and storage/network failures.

Archive integrity verification, PBS verification status, restore planning/conflict preflight, actual restore, physical Android accessibility/network/TLS testing and production certification remain gated.
