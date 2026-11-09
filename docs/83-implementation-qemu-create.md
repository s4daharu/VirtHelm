# Guarded empty QEMU create workflow — 2026-11-09

This increment continues **GUEST-05 / M4 provisioning** after template discovery and the guarded full-template clone slice. It adds a deliberately constrained QEMU creation workflow that creates an empty, stopped VM configuration without allocating storage or attaching network/media resources.

## Reviewed upstream contract

Current upstream Proxmox QEMU source confirms:

- create endpoint: `POST /nodes/{node}/qemu`;
- destination allocation: `VM.Allocate` on `/vms/{vmid}` (or an explicitly selected pool, which VirtHelm does not use here);
- CPU options require `VM.Config.CPU`;
- memory options require `VM.Config.Memory`;
- general options such as name/onboot require `VM.Config.Options`;
- newly allocated disks require `Datastore.AllocateSpace`;
- bridges/VLANs require `SDN.Use`;
- start-after-create requires `VM.PowerMgmt`.

The server also performs quorum and VMID-unused checks before creating the VM configuration.

References: [official API viewer](https://pve.proxmox.com/pve-docs/api-viewer/) and
[official QEMU API source at 530b95c](https://git.proxmox.com/?p=qemu-server.git;a=blob;f=src/PVE/API2/Qemu.pm;hb=530b95c630316d76f06c74f9c2488b76aee194fc)
(`create_vm`, `check_vm_modify_config_perm`, and `qmcreate` worker registration).
These are upstream source contracts, not deployed PVE 8.4/9.2 fixtures.

VirtHelm intentionally sends only:

- `vmid`;
- `name`;
- `cores`;
- `memory`;
- `onboot`.

It sends no disk, ISO/CD-ROM, network, storage, pool, HA, restore/archive or start parameter. The resulting VM is therefore an **empty stopped QEMU shell**. Unspecified QEMU configuration remains under Proxmox defaults.

## Why LXC creation remains gated

Upstream LXC create requires an `ostemplate` and storage/rootfs handling. The server checks access to the template content and requires `Datastore.AllocateSpace` on the destination storage; privileged containers additionally require `Sys.Modify` on `/`.

VirtHelm does not yet expose a reviewed, bounded `vztmpl` content browser or rootfs-storage compatibility contract. LXC creation is therefore not enabled by this milestone. This avoids inventing template/storage choices or weakening storage authorization checks.

## UI and input boundary

The Guests screen exposes **Create VM** only when:

- an active profile exists;
- the current inventory is fresh and free of malformed guest records;
- no refresh is in progress;
- at least one node is currently reported online.

The create page supports:

- online destination-node selection;
- VMID 100–999999999, with a server suggestion when available;
- conservative 1–63 character letters/numbers/hyphens VM name;
- 1–64 CPU cores;
- 128–262144 MiB memory;
- optional `onboot` flag.

The final confirmation requires the operator to type the exact destination VMID. The dialog explicitly states that the VM has no disk, network or installation media and will not be started.

## Preflight and single-shot submission

Immediately before the POST, the controller requires:

1. the original profile and connection generation are still active;
2. the app is foregrounded and Android default-network state is not unavailable;
3. the current inventory is fresh, clean and unchanged;
4. the chosen node exists exactly once and is still online;
5. the destination VMID is absent from the current inventory;
6. a second live inventory still reports the chosen node online and the VMID unused;
7. effective destination permissions report `VM.Allocate`, `VM.Config.CPU`, `VM.Config.Memory` and `VM.Config.Options`;
8. `GET /cluster/nextid?vmid={vmid}` still confirms server-side VMID availability.

Only after those checks is one create POST issued.

Mutation POSTs are never automatically retried. A returned UPID must match the requested node, VMID and `qmcreate` worker before it is registered with the existing task engine. The exact guest key and the cluster-wide destination VMID remain single-flight locked until terminal task handling is followed by a new, clean authoritative inventory refresh. Both reservations participate in task completion and uncertainty handling. Create and clone cannot reserve the same destination on different nodes or across QEMU/LXC, and a newly discovered provisioning destination cannot authorize a concurrent power action. Timeout, unavailable task verification, authentication loss, ambiguous transport failure or an unexpected create response retains the cluster-wide destination lockout. A malformed or failed reconciliation read cannot release it.

The controller takes the originating connection generation explicitly. Create and clone confirmation dialogs observe the controller directly, redact the old identity on profile/reconnect/source invalidation, and disable submission when inventory or target availability changes. Dialog-owned text controllers are disposed with the dialog route, not while its exit transition still renders.

This is an at-most-one client submission per accepted operation, not a claim of distributed exactly-once execution. Proxmox remains authoritative for races with other clients, quorum and final validation.

## Regression coverage

This milestone adds coverage for:

- normalized/invalid create request inputs;
- exact QEMU create endpoint and form body;
- absence of disk/network/storage/start/pool/HA/restore parameters;
- no automatic retry after an ambiguous create POST failure;
- VMID suggestion and collision recheck;
- required destination privilege preflight;
- denial before POST when a required privilege is missing;
- UPID registration and provisioning-target lockout;
- Guests-screen entry into the create wizard.

The [branch cross-check](84-qemu-create-branch-cross-check-2026-11-09.md) adds
cross-node/create-clone reservations, newly discovered destination power guards,
same-profile generation rejection, every preflight-await race, privilege denials,
ambiguous/definitive failures, task reconciliation and dialog lifecycle/redaction
regressions. The form and confirmation also have a synthetic 320dp/200%-text check.

Source-smoke checks also require the create model, API boundary, controller flow, UI entry and this implementation record.

## Deliberately deferred

This milestone does **not** add QEMU disks, storage selection, ISO/media selection, NIC/bridge configuration, cloud-init, pool/HA placement, automatic start, restore/import, LXC creation, linked/cross-node clone, migration, configuration editing, destructive deletion, backup execution or snapshot mutation.

Live PVE 8.4/9.2 create/ACL/quorum fixtures and physical Android confirmation/accessibility/network-transition testing remain release gates. Source/CI success does not constitute production certification.

The original branch introduced **0.1.36**; the pre-merge safety audit advances the app to **0.1.37**.
