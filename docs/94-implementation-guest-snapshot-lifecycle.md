# Guarded guest snapshot rollback and deletion

This milestone completes the bounded snapshot lifecycle for QEMU/LXC guests:
create (already implemented), stopped-only non-RAM rollback, and snapshot
deletion. It remains a source-level, synthetic-test implementation. No live
PVE mutation, PVE 8.4, restricted-ACL or physical-Android evidence is claimed.

## Scope

- The Recovery tab snapshot rows are tappable on mobile and open a bottom sheet
  with **Roll back to this snapshot** and **Delete this snapshot** actions.
- Both actions require the operator to type the exact snapshot name in a
  route-owned confirmation dialog. The dialog expires when the profile,
  connection generation or exact guest changes.
- The `current` pseudo-entry is never actionable. It is not a restore point.
- No snapshot-description editing, scheduled snapshot, retention, backup
  verification, restore execution or template snapshot path is added.

## Contract

Reviewed upstream contracts:

- QEMU: [PVE/API2/Qemu.pm](https://github.com/proxmox/qemu-server/blob/master/src/PVE/API2/Qemu.pm)
  - `DELETE /nodes/{node}/qemu/{vmid}/snapshot/{snapname}`
    (`VM.Snapshot`, worker `qmdelsnapshot`)
  - `POST /nodes/{node}/qemu/{vmid}/snapshot/{snapname}/rollback`
    (worker `qmrollback`)
- LXC: [PVE/API2/LXC/Snapshot.pm](https://github.com/proxmox/pve-container/blob/master/src/PVE/API2/LXC/Snapshot.pm)
  - `DELETE /nodes/{node}/lxc/{vmid}/snapshot/{snapname}`
    (`VM.Snapshot`, worker `vzdelsnapshot`)
  - `POST /nodes/{node}/lxc/{vmid}/snapshot/{snapname}/rollback`
    (worker `vzrollback`)
- Snapshot names use Proxmox's `pve-configid` format: 2–40 characters, start
  with a letter, then letters/numbers/`_`/`-`. The app validates this before a
  mutation and URL-encodes the path segment.

The delete request sends no `force` field. The rollback request sends no
`start` field; VirtHelm does not ask Proxmox to power the guest on after the
rollback.

## Safety boundary

Both mutations share the existing guest-operation single-flight and
uncertain-outcome machinery:

1. Reject stale profile IDs, connection generations, background/offline state,
   dirty or refreshing inventory, templates and unknown guest states.
2. Re-read a clean live inventory and require the exact node/type/VMID identity
   and unchanged state. Rollback additionally requires a stopped guest.
3. Check the exact guest permission hint: `VM.Snapshot` for delete and
   `VM.Snapshot.Rollback` for rollback.
4. Re-read a complete snapshot list and require exactly one target with the same
   name, parent, description, creation time and QEMU memory-state flag shown to
   the operator. A disappeared, renamed or replaced snapshot blocks the
   mutation.
5. Reject rollback when the snapshot reports QEMU RAM state (`vmstate`). Those
   snapshots can auto-start the guest under Proxmox semantics and need a
   separate power-aware workflow.
6. Perform a final exact-guest `/status/current` read and repeat the session,
   freshness and network checks.
7. Submit exactly one POST or DELETE without retry. A transport/5xx response
   with an uncertain outcome locks the guest until server task history and a
   post-terminal inventory read resolve the operation.
8. Accept only a task UPID with the exact node, VMID and worker
   `qmdelsnapshot`/`vzdelsnapshot` or `qmrollback`/`vzrollback`. Mismatched
   identifiers are treated as uncertain outcomes.

Stopping the guest is deliberately the operator's job before rollback. The
upstream rollback worker can stop a running guest, but this slice does not
silently invoke that power side effect or request `VM.PowerMgmt`.

Snapshots are not backups. A successful rollback or delete task is not evidence
that the guest boots, that an application is healthy, or that a backup can be
restored.

## Mobile UI behavior

- Snapshot rows use the whole-row target and a trailing chevron instead of
  hiding actions behind a tiny overflow control.
- The action sheet uses full-width list rows with explicit consequences and
  disables an action with a plain-language reason when the guest is running,
  the snapshot includes RAM state, inventory is stale or another operation is
  pending.
- Confirmation content is scrollable for narrow phones and large text. The
  typed field is owned by the dialog route and is disposed with it.
- The Recovery copy now distinguishes implemented snapshot lifecycle actions
  from still-gated archive integrity verification, restore execution and
  configuration editing.

## Automated coverage

- Gateway tests verify the exact DELETE/POST paths, empty mutation payloads,
  strict worker and VMID matching, safe snapshot-name validation, and
  pre-I/O rejection of running/RAM-state rollback.
- Controller tests cover delete/rollback submission, permission denial,
  running/RAM-state preflight rejection, missing/changed snapshot metadata,
  task registration and ambiguous-outcome lockout after a failed DELETE.
- Widget coverage opens the mobile action sheet, verifies a running guest's
  rollback action is disabled with a reason, and completes the typed-name
  delete confirmation.
- Existing profile/reconnect redaction, inventory freshness, single-flight and
  post-terminal reconciliation regressions remain in the full suite.
- At implementation time, the pinned Flutter 3.44.4 suite passed **382 runtime
  tests from 303 declarations** locally. Current-head CI remains authoritative.

## Deferred and release gates

- Live PVE 8.4/9.2 snapshot storage/backend, lock, ACL, task/fault and
  replication fixtures.
- Rollback of QEMU snapshots that include RAM state or auto-start behavior.
- Rollback while running, power-aware rollback, scheduled snapshots,
  descriptions, retention and snapshot trees.
- Archive integrity verification, PBS verification, tested restore and any
  restore mutation.
- Physical Android confirmation/accessibility/network-transition testing.
