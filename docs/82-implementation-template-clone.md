# Guarded template clone workflow — 2026-11-09

This increment implements the first **GUEST-015 / M4 provisioning mutation**: a deliberately constrained full clone from a QEMU or LXC template. It builds directly on template discovery, exact-guest permission hints, clean live inventory guards, and the existing single-shot UPID task lifecycle.

## Reviewed contract

Current upstream Proxmox source confirms the clone families at:

- QEMU: `POST /nodes/{node}/qemu/{vmid}/clone` in `proxmox/qemu-server` `src/PVE/API2/Qemu.pm`.
- LXC: `POST /nodes/{node}/lxc/{vmid}/clone` in `proxmox/pve-container` `src/PVE/API2/LXC.pm`.
- Free/collision VMID preflight: `GET /cluster/nextid`, with an explicit `vmid` query used for the last-moment availability check.

The QEMU source documents `VM.Clone` on the source plus `VM.Allocate` on the destination (or destination pool), with `Datastore.AllocateSpace` on used storage and `SDN.Use` on used bridge/vnet where applicable. LXC likewise requires source `VM.Clone` and destination/pool `VM.Allocate`. These source findings establish the implementation contract but do **not** replace live PVE 8.4/9.2 fixtures.

VirtHelm sends only:

- `newid`;
- `full=1`;
- `name` for QEMU or `hostname` for LXC.

It intentionally sends no target node, pool, storage override, linked-clone request, or other optional clone parameter. The first workflow is therefore a **full same-node clone using Proxmox default storage placement**.

## UI and validation

Templates now expose **Clone template** instead of any power action. The clone page:

- obtains a suggested free VMID from `/cluster/nextid` when available;
- accepts VMID 100–999999999;
- restricts the requested name/hostname to a conservative 1–63 character DNS-safe subset;
- explains that linked clones, cross-node targets, explicit storage selection, create-from-scratch, and migration remain gated;
- requires the operator to type the exact destination VMID in the final confirmation dialog.

A suggested clone name is sanitized locally; no template name is trusted as a valid destination hostname/name automatically.

## Preflight and write safety

Immediately before submission the controller requires all of the following:

1. the active profile and connection generation still match the opened template;
2. Android default-network state is not unavailable and the app is foregrounded;
3. the current inventory is fresh, clean, and unchanged;
4. the exact source still exists once and is still marked as a template;
5. the destination VMID is absent from a fresh server inventory;
6. effective `VM.Clone` is reported on the source `/vms/{vmid}` path;
7. effective `VM.Allocate` is reported on the destination `/vms/{newid}` path;
8. `/cluster/nextid?vmid={newid}` still confirms the destination is free.

Only then is one clone POST issued. POSTs are never automatically retried. A returned UPID is tracked by the existing task engine, terminal status is not treated as success without the exit status, and a terminal task is followed by an authoritative inventory refresh. Ambiguous POST/network/response outcomes place the source in the existing uncertain-operation lockout so another clone cannot be submitted casually.

The source/destination permission probes are useful preflight hints, not complete authorization. This first slice does not infer `Datastore.AllocateSpace` or `SDN.Use` from unrelated ACL paths. Proxmox remains final authority; a 403 is surfaced and the write is not replayed.

## Automated regression coverage

Coverage added for:

- clone request normalization and invalid VMID/name rejection;
- QEMU full-clone form body and exact endpoint;
- LXC `hostname` form field;
- `/cluster/nextid` suggestion/collision checks;
- exact source/destination permission paths;
- ambiguous clone POST single-shot behavior;
- controller capability denial before POST;
- successful controller preflight, UPID registration, and source lock;
- template-detail entry into the clone wizard.

Repository source-smoke checks also require the clone model, API boundary, controller guard, wizard entry point, and this implementation record.

## Deliberately deferred

This milestone does **not** implement linked clones, target-node selection, explicit destination storage, pools, create-from-scratch QEMU/LXC wizards, migration, template conversion, snapshot mutation, backup execution, restore, or destructive guest deletion.

Live PVE 8.4/9.2 clone parameter/ACL/storage/network/task fixtures and physical Android accessibility/network/process-loss testing remain release gates. The feature must not be described as production-certified until those gates pass.

The app version advances to **0.1.35**.
