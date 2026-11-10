# 87. Guarded guest deletion implementation

Status: **source-level implemented; live PVE 8.4/9.2 destructive-operation and physical-device gates remain open**  
Date: 2026-11-10

## Scope

This increment delivers the first bounded GUEST-07 destructive workflow for deleting an existing QEMU VM or LXC container.

The flow is intentionally narrower than Proxmox's full destroy API:

- stopped, non-template guests only;
- one exact profile/node/type/VMID at a time;
- explicit recovery-backup acknowledgement;
- named guest + VMID confirmation using the exact phrase `DELETE <name> <vmid>`;
- current-token `VM.Allocate` capability hint;
- exactly one DELETE mutation and strict destroy-task UPID tracking;
- no automatic retry after a deletion attempt.

## Upstream contract reviewed

Current Proxmox QEMU and LXC contracts expose:

- `DELETE /nodes/{node}/qemu/{vmid}` for QEMU;
- `DELETE /nodes/{node}/lxc/{vmid}` for LXC;
- `VM.Allocate` on `/vms/{vmid}` as the deletion privilege;
- `qmdestroy` and `vzdestroy` task workers respectively.

Deleting a guest is destructive: used/owned volumes can be removed with the guest, snapshots are not backups, and server-side protection/HA/lock/storage rules remain authoritative.

VirtHelm deliberately sends none of the optional destructive knobs in this first slice. It does not expose `skiplock`, `purge`, `destroy-unreferenced-disks`, template deletion, running-guest deletion, disk detach/remove, or bulk deletion.

## Preflight and mutation safety

Before the single DELETE, the controller revalidates:

1. originating profile and connection generation;
2. foreground/default-network availability;
3. a fresh, clean, unchanged inventory;
4. exact source kind/node/VMID identity;
5. the target is still non-template and stopped;
6. no pending or uncertain operation owns the guest or its cluster-wide VMID;
7. the current token reports `VM.Allocate` on the exact guest path.

The guest key and cluster-wide VMID key are reserved synchronously before asynchronous verification. This blocks concurrent power, create, clone, migration, or second-deletion attempts for that VMID in the current session.

After those checks VirtHelm performs exactly one DELETE. The response must be a source-node/VMID-matched `qmdestroy` or `vzdestroy` UPID. An ambiguous transport/result failure or mismatched task identifier enters the existing uncertain-operation lockout and is never automatically replayed. Task completion remains locked until a later authoritative inventory refresh reconciles the guest's state.

## Destructive confirmation

The guest action bar exposes deletion only while the exact current guest is stopped and non-template.

The dialog:

- identifies guest kind, node and VMID;
- warns that guest-owned volumes and snapshots can be permanently destroyed;
- states that snapshots are not backups;
- requires an explicit checkbox acknowledging that any required recoverable backup was verified separately;
- requires the exact named guest + VMID confirmation phrase;
- explains that identity/state/permission are revalidated immediately before one DELETE;
- states that VirtHelm will not automatically retry the destructive request.

The backup checkbox is an operator safety gate, not an automated recoverability claim. This source slice does not yet prove backup freshness, archive integrity, quorum, HA evacuation state, storage ownership, or application-level restoreability.

## Verification added

Synthetic coverage now checks:

- QEMU uses DELETE on the exact guest path and accepts only a matching `qmdestroy` UPID;
- LXC deletion refuses a running container before I/O and accepts only `vzdestroy`;
- mismatched destroy workers become uncertain outcomes;
- controller deletion requires a stopped guest and `VM.Allocate`;
- successful submission registers a tracked task and reserves the guest;
- ambiguous deletion remains locked and cannot be retried after a normal refresh;
- source smoke checks guard the gateway, controller, UI confirmation and this document.

## Remaining gates

This is not production certification. Disposable PVE 8.4 and 9.2 destructive testing remains required for protected guests, HA-managed guests, server locks, local/shared/ZFS/Ceph storage, backup jobs, ACL inheritance, restricted API tokens, task failure, and network interruption after DELETE.

Physical Android validation remains required for typed destructive confirmation, TalkBack, large text, route/profile changes, Wi-Fi/VPN loss and task-state reconciliation.

Automated backup/quorum/HA safety proof, template deletion, running deletion, optional purge/skip-lock controls, disk detach/remove, snapshot/backup mutation and bulk destructive operations remain gated.
