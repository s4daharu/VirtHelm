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

## Preflight and exactly-once write behavior

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

Mutation POSTs are never automatically retried. A returned UPID is registered with the existing task engine. The provisioning target remains single-flight locked until terminal task handling is followed by an authoritative inventory refresh. Timeout, unavailable task verification, authentication loss, ambiguous transport failure or an unexpected create response moves the node/VMID target into the existing uncertain-operation lockout.

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

Source-smoke checks also require the create model, API boundary, controller flow, UI entry and this implementation record.

## Deliberately deferred

This milestone does **not** add QEMU disks, storage selection, ISO/media selection, NIC/bridge configuration, cloud-init, pool/HA placement, automatic start, restore/import, LXC creation, linked/cross-node clone, migration, configuration editing, destructive deletion, backup execution or snapshot mutation.

Live PVE 8.4/9.2 create/ACL/quorum fixtures and physical Android confirmation/accessibility/network-transition testing remain release gates. Source/CI success does not constitute production certification.

The app version advances to **0.1.36**.
