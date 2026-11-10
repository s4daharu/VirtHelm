# GUEST-03 Partial: Guarded One-Off Guest Backup Start

**Date:** 2026-11-11  
**Version:** 0.1.42  
**Milestone:** M4 recovery operations / GUEST-03 partial

## Scope delivered

VirtHelm now exposes a guarded **Start backup** action from a non-template QEMU or LXC guest's Recovery tab when the current live read model contains at least one active storage on that guest's node whose content types include `backup`.

This slice starts one Proxmox `vzdump` task. It does **not** claim that task submission or task success proves a recoverable archive.

## Mutation contract

The request is deliberately constrained to:

- `POST /nodes/{node}/vzdump`
- `vmid={exact guest VMID}`
- `storage={operator-selected active backup storage}`
- `mode=snapshot`

There is **no pruning** or retention mutation. VirtHelm also sends no hook/script, fleecing, bandwidth, performance, ionice, protected, notes-template, compression, mail or other advanced vzdump tuning fields in this slice.

For a single VMID, the reviewed upstream vzdump implementation uses that VMID as the task id and returns a `vzdump` UPID. VirtHelm accepts the response only when the returned UPID has the exact source node, `vzdump` worker, exact VMID, non-empty auth identity and expected UPID shape. A malformed or mismatched post-response is treated as an unknown outcome.

## Preflight and authorization boundary

Immediately before the one mutation attempt, the controller:

1. requires the originating profile and connection generation to still be active;
2. requires foreground/default-network availability plus a fresh, clean write-safe inventory;
3. re-reads cluster inventory and requires exactly one unchanged non-template guest at the original node/type/VMID and unchanged running/stopped state;
4. re-reads effective permissions for the exact guest and requires `VM.Backup`;
5. re-reads `/nodes/{node}/storage` and requires the selected storage to still be enabled, active, and advertise `backup` content;
6. re-reads effective permissions for `/storage/{storage}` and requires `Datastore.AllocateSpace`;
7. submits exactly one vzdump POST.

The permission reads are defensive capability hints. Proxmox remains authoritative for server-side authorization and backend-specific backup constraints.

## Concurrency and uncertain outcomes

Backup start shares the existing guest plus cluster-wide VMID reservation used by other guest mutations. A guest cannot be backed up concurrently through VirtHelm with another power, snapshot, migration, provisioning, deletion, or backup operation that targets the same reservation.

Mutation requests are never automatically retried. If the request may have executed but VirtHelm cannot validate its result, the guest remains locked for the connection session until the operator checks server task history and reconnects.

## Recovery truth boundary

The Recovery tab continues to display recent guest-scoped `vzdump` task outcomes. The UI now states explicitly that:

- a submitted task is not archive verification;
- a task reporting success is not proof that a backup archive exists at the expected location;
- no archive integrity check is performed;
- no restore test is performed;
- restore remains unavailable.

Backup scheduling, retention/pruning, archive inventory and integrity verification, PBS-specific browsing/workflows, restore, advanced vzdump tuning, and destructive recovery operations remain gated.

## Automated coverage

Synthetic regressions cover:

- active/enabled `backup` storage filtering;
- exact one-POST body containing only `vmid`, `storage`, and `mode=snapshot`;
- rejection of invalid storage identifiers before I/O;
- strict `vzdump` UPID node/VMID matching and unknown-outcome handling;
- fresh `VM.Backup` enforcement;
- fresh selected-storage capability revalidation;
- `Datastore.AllocateSpace` enforcement on the selected storage path;
- tracked-task registration and guest lockout;
- prevention of replay after an ambiguous POST outcome;
- source-smoke guards for the gateway/controller/UI/document contract.

## Remaining validation gates

This source-level milestone is not production certification. Disposable PVE 8.4 and 9.2 fixtures are still required for running/stopped QEMU and LXC backups across directory, NFS/CIFS and PBS-style backup storage, restricted ACLs/tokens, storage loss/full conditions, guest locks, concurrent server-side backup jobs, task failures and transport ambiguity. Physical Android confirmation, accessibility, network-transition, TLS and secure-storage validation also remain open.
