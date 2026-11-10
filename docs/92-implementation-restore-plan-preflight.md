# Implementation milestone — BKP-007/BKP-008 restore plan and conflict preflight

**Date:** 2026-11-11  
**Version target:** 0.1.45  
**Scope:** guided, read-only restore planning for one currently visible QEMU/LXC backup archive. The restore mutation remains gated.

## Delivered boundary

VirtHelm can now turn an exact-guest archive already loaded in **Guest → Recovery** into a point-in-time restore plan for the current node and a different target VMID. The operator chooses the alternate VMID and one currently active, type-compatible target storage. Running the preflight performs reads only; it never calls a restore endpoint and never creates a task.

This is the first bounded implementation of **BKP-007** and **BKP-008**. It intentionally does not implement existing-target overwrite, cross-node restore, device/network/storage mapping, archive integrity verification, or the actual restore request.

## Fresh preflight evidence

Immediately after the operator chooses the target, the controller revalidates:

1. the active profile/generation and exact source guest identity;
2. a fresh clean cluster inventory, rejecting malformed guest records;
3. the exact selected archive on the exact source backup storage;
4. fresh node storage state for both source backup storage and selected target storage;
5. target node online state;
6. cluster-wide target VMID availability;
7. target content compatibility: `images` for QEMU or `rootdir` for LXC;
8. effective `VM.Allocate` on the target VMID;
9. effective `Datastore.AllocateSpace` on the target storage.

Any missing evidence is rendered as a blocker. A conflict never becomes an overwrite offer in this milestone.

## Capacity boundary

The card may show the archive's reported size beside the target storage's currently reported available bytes. That comparison is context only. Backup archive size is compressed backup metadata and is **not** treated as a restored-disk allocation estimate, so the preflight never claims capacity sufficiency.

## Safety properties

- No new mutation endpoint is implemented.
- No POST, PUT, or DELETE is issued by restore planning.
- Cross-node planning is rejected.
- Existing target VMIDs are blocked; overwrite restore is not exposed.
- Archive identity is freshly re-read before a plan can be marked complete.
- Incomplete storage inventory blocks a complete preflight.
- ACL reads are hints for a future restore contract, not proof that every server-side restore requirement is satisfied.
- A **Preflight complete** result means only that this bounded read-only evidence set passed at that moment. It is not restore authorization, integrity verification, tested restore evidence, or a recoverability guarantee.

## UI

Each loaded archive exposes **Plan restore** when a compatible same-node destination storage is currently visible. The dialog states the no-mutation boundary before collecting an alternate VMID. The resulting card shows source visibility, node state, VMID conflict state, storage compatibility, ACL hints, blockers, capacity context, and a point-in-time disclaimer.

Changing or refreshing archive storage clears previous restore-plan evidence.

## Automated coverage

Synthetic coverage now verifies:

- restore-plan request normalization and validation;
- explicit blocked vs preflight-complete evidence states;
- fresh archive/storage/VMID/ACL preflight with zero mutation submissions;
- occupied target VMID conflict blocking;
- Recovery UI flow from visible archive to alternate VMID preflight card;
- source smoke assertions for the model/controller/UI boundary and this document.

These are source/synthetic checks only. Real PVE 8.4/9.2 restore/storage/ACL fixtures and physical Android accessibility/network lifecycle testing remain required before any restore execution capability can be promoted.

## Still gated

The following remain separate milestones:

- QEMU/LXC restore mutation and task reconciliation;
- overwrite/replace restore;
- cross-node restore;
- storage/device/network mapping and hardware-compatibility handling;
- PBS verification state and checksum/integrity evidence;
- tested-restore declarations (BKP-010);
- DR/RTO/RPO evidence and automated restore drills.

The next restore milestone must define and independently review the exact Proxmox restore mutation contracts, privilege model, overwrite semantics, task workers, uncertain-outcome behavior, and post-restore evidence before any write is enabled.
