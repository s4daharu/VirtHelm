# Backup, Restore and Proxmox Backup Server (PBS) Plan
PVE backup operations and native PBS administration have **different** API surfaces. PBS 4.2 (2026-04-29) is a separately researched, separately authenticated optional integration. Do not treat backup existence as proof of restorable data.

## Tiered delivery
- **F1 PVE read-only:** backup schedules, recent tasks, backup storage/status, latest backup per guest if available, retention settings read-only; identify data gaps and ACLs.
- **F1 guarded PVE execution:** one-off backup and progress; explicit storage, mode, bandwidth/notification settings only where API supports them; restore remains behind a separate irreversible-operation review.
- **F2 guided restore:** discover appropriate archive/snapshot source, show age and size, target VMID/overwrite/storage, hardware constraints, confirmation and UPID progress; “restore finished” is not “DR validated.”
- **F4 PBS connector:** own base URL, auth mode, certificate trust and permission model; datastore browsing, backup groups/snapshots, namespaces, verify/prune/GC job state, remote sync, encryption metadata and status only after PBS API/schema tests.
- **F4 advanced PBS 4.2:** datastore move groups/namespaces, S3-backed store metrics and sync encryption/concurrency are **feature research candidates**, not automatically supported VirtHelm mobile actions.

## Recovery confidence card
Show latest backup timestamp (with timezone), backup location and provenance (PVE/PBS), verification job status where accessible, retention risk, and separately recorded **last tested restore** (manual operator attestation or verified lab test). Clearly distinguish:
1. backup task accepted;
2. backup job success;
3. backup archive verified;
4. restore procedure exercised;
5. application-level recovery validated.
Never collapse these into one green badge.

## Restore safety workflow
**Select** guest/backup, **inspect** recovery point, **plan** target or alternate VMID and datastore, **verify** sufficient space and ACLs, **warn** if existing target overwritten, **confirm** exact name/VMID, **submit** once, **track** asynchronous task and **post-check**. Unknown writes are not retried. For production restore, require an operator acknowledgement of service impact and documented recovery objective. Record provenance without storing raw task logs.

## Retention and backup policies
Display effective schedule and retention if readable; propose policy review only. Retention edits or prune/GC actions are high-risk: some data will become irrecoverable and there is no reliable undo. Provide a projected affected-item count from server-side dry-run or explicit unknown warning; never fake dry-run. Preserve encryption-key handling entirely outside the app unless a formally reviewed key-management RFC exists.

## Compatibility/test matrix
PVE 8.4 and 9.2: backup status, storage type and ACL, one-off backup task, restore into disposable guest. PBS 4.2: independent login/token realm, datastore/namespace/verification metrics, revoked rights, encrypted/unavailable snapshots, S3-backed storage visibility. Separate fixture sets and support contracts; PVE version does not imply PBS version.

## Sources
- PVE API viewer: https://pve.proxmox.com/pve-docs/api-viewer/
- PBS API viewer: https://pbs.proxmox.com/docs/api-viewer/index.html
- PBS 4.2 release: https://proxmox.com/en/about/company-details/press-releases/proxmox-backup-server-4-2
