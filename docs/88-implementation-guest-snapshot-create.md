# 88. Guarded guest snapshot creation implementation

Status: **source-level implemented; live PVE 8.4/9.2 snapshot/storage and physical-device gates remain open**  
Date: 2026-11-10

## Scope

This increment delivers the first bounded GUEST-02 mutation: create-only snapshots for existing non-template QEMU VMs and LXC containers.

The workflow is intentionally narrow:

- one exact profile/node/type/VMID at a time;
- the guest must still have the same reviewed live state and that state must be running or stopped;
- conservative snapshot names only;
- current-token `VM.Snapshot` capability hint;
- a fresh complete snapshot-list collision check immediately before mutation;
- exactly one snapshot POST and strict task-UPID tracking;
- no automatic mutation retry.

Snapshot rollback and deletion remain unavailable. QEMU RAM-state capture, snapshot descriptions, retention, scheduling and backup/restore are also outside this slice.

## Contract reviewed

VirtHelm uses the existing QEMU/LXC snapshot collection:

- `GET /nodes/{node}/qemu/{vmid}/snapshot`
- `POST /nodes/{node}/qemu/{vmid}/snapshot`
- `GET /nodes/{node}/lxc/{vmid}/snapshot`
- `POST /nodes/{node}/lxc/{vmid}/snapshot`

Creation requires `VM.Snapshot` on the exact guest path. This slice sends only `snapname`. It deliberately does not send QEMU `vmstate`, so VirtHelm does not request RAM-state capture.

Expected workers are `qmsnapshot` for QEMU and `vzsnapshot` for LXC. Returned task IDs must match the exact source node, VMID and worker family.

## Preflight and mutation safety

Before the single POST, the controller revalidates:

1. originating profile and connection generation;
2. foreground/default-network availability;
3. a fresh, clean, unchanged cluster inventory;
4. exact source kind/node/VMID identity and non-template state;
5. the guest still has the same reviewed running/stopped state;
6. no pending or uncertain operation owns the guest or its cluster-wide VMID;
7. the current token reports `VM.Snapshot` on the exact guest path;
8. a freshly loaded snapshot inventory is complete, non-truncated, and does not already contain the requested name.

The guest key and cluster-wide VMID key are reserved synchronously before asynchronous verification. That keeps snapshot creation single-flight with power actions, create/clone, migration and deletion in the current session.

After those checks VirtHelm performs exactly one POST. An ambiguous transport/result failure or mismatched UPID becomes the existing uncertain-operation lockout and is never automatically replayed.

## User experience

The Recovery tab retains on-demand snapshot inventory and recent backup-task visibility. For eligible non-template guests it now adds **Create snapshot**.

The dialog:

- identifies exact node, guest kind and VMID;
- states that snapshots are not backups;
- states that QEMU RAM-state capture is not requested;
- accepts a conservative 1–64 character snapshot name using letters, numbers, underscores and hyphens;
- explains the live identity/state/permission/name-collision revalidation and one-POST/no-retry rule.

After submission, local snapshot inventory is cleared so an old list is not presented as if it already contains the new snapshot. The operator follows completion in Tasks and reloads snapshots afterward.

## Verification added

Synthetic coverage checks:

- QEMU uses one POST to the exact snapshot collection with only `snapname`;
- LXC accepts only the `vzsnapshot` worker;
- invalid names fail before I/O;
- mismatched snapshot workers are classified as uncertain outcomes;
- controller creation requires `VM.Snapshot`;
- an existing exact snapshot name blocks the POST;
- successful submission registers a tracked task and reserves the guest/VMID;
- an ambiguous POST remains locked and cannot be retried after a normal refresh;
- source smoke checks guard the request model, gateway, controller, Recovery UI, tests and this document.

## Remaining gates

This is not production certification. Disposable PVE 8.4 and 9.2 testing remains required across QEMU/LXC storage backends, running and stopped guests, guest/storage locks, HA-managed guests, ACL inheritance, restricted API tokens, snapshot-name edge cases, task failure and network interruption after POST.

Physical Android validation remains required for the create dialog, TalkBack, large text, route/profile changes, Wi-Fi/VPN loss and task-state reconciliation.

QEMU `vmstate`, snapshot descriptions, rollback/delete, scheduled/retained snapshots, backup execution/archive verification/restore and production release certification remain gated.
