# 85. Guarded LXC create implementation

Status: **source-level implemented; live PVE 8.4/9.2 mutation and physical-device gates remain open**  
Date: 2026-11-09

## Scope

This increment completes the bounded container-creation half of the M4 create/clone milestone. VirtHelm now exposes an Android LXC wizard that creates only an **unprivileged** container from an existing Proxmox `vztmpl` image.

The reviewed request is intentionally small:

- destination node and cluster-wide VMID,
- hostname,
- CPU cores,
- memory,
- `onboot`,
- an existing `ostemplate`,
- a rootdir-capable `storage`,
- `unprivileged=1`.

VirtHelm does **not** send a password, SSH keys, NIC configuration, explicit rootfs size, privileged mode, start-after-create, pool, HA, restore input, nesting/features, hooks, mounts or arbitrary options. With no explicit `rootfs` parameter, the reviewed upstream create path allocates its default 4 GiB root filesystem on the selected storage.

## Upstream contracts reviewed

The implementation was checked against current upstream Proxmox source:

- `proxmox/pve-container`, `src/PVE/API2/LXC.pm`
  - create endpoint: `POST /nodes/{node}/lxc`;
  - `ostemplate` is required;
  - new containers default to unprivileged and privileged creation additionally requires `Sys.Modify`;
  - rootdir storage requires `Datastore.AllocateSpace`;
  - omitting explicit `rootfs` uses the selected storage and the server's default 4 GiB allocation;
  - the asynchronous worker is `vzcreate`.
- `proxmox/pve-container`, `src/PVE/LXC.pm`
  - `cores` maps to `VM.Config.CPU`;
  - `memory` maps to `VM.Config.Memory`;
  - `hostname` maps to `VM.Config.Network`;
  - `onboot` falls under `VM.Config.Options`.
- `proxmox/pve-storage`, `src/PVE/API2/Storage/Content.pm`
  - `GET /nodes/{node}/storage/{storage}/content?content=vztmpl` lists container-template content;
  - storage content reads require `Datastore.Audit` or `Datastore.AllocateSpace`.

## Discovery and permission preflight

Before confirmation, VirtHelm reads `/nodes/{node}/storage`, keeps only active/enabled pools, and derives:

- root filesystem choices from pools advertising `rootdir`;
- template sources from pools advertising `vztmpl`, followed by the bounded storage-content query above.

Malformed or inaccessible template-storage results mark discovery incomplete and disable submission.

Immediately before the single create POST, the controller revalidates a fresh clean inventory and rediscovery, confirms the selected template/rootdir storage still exists, rechecks the VMID with `/cluster/nextid?vmid=...`, and performs effective-permission hints for:

- destination `/vms/{vmid}`: `VM.Allocate`, `VM.Config.CPU`, `VM.Config.Memory`, `VM.Config.Network`, `VM.Config.Options`;
- root filesystem `/storage/{storage}`: `Datastore.AllocateSpace`;
- template `/storage/{template-storage}`: `Datastore.Audit` or `Datastore.AllocateSpace`.

These client probes are defensive hints only. Proxmox remains authoritative for quorum, final ACL evaluation, template validity, storage availability, VMID uniqueness and all create validation.

## Mutation safety

The LXC path inherits the provisioning protections already used by QEMU create and template clone:

- exact active profile and connection generation;
- foreground-only mutation from a clean current inventory;
- exact online destination-node verification;
- cluster-wide destination-VMID reservation shared across QEMU/LXC create and clone;
- typed destination-VMID confirmation;
- synchronous reservation before asynchronous preflight;
- exactly one POST with no automatic mutation retry;
- strict `UPID` validation for node, `vzcreate`, VMID and user;
- ambiguous POST/result failures become uncertain-operation lockouts;
- task polling owns the reservation through terminal outcome;
- post-terminal authoritative inventory refresh reconciles state.

## Verification added

Synthetic coverage now checks:

- request validation and template-volume shape;
- active `rootdir` + `vztmpl` discovery;
- exact reviewed LXC POST fields and absence of gated credential/network/start/pool/restore fields;
- `vzcreate` UPID validation and ambiguous-result classification;
- controller-level option revalidation, destination/storage permissions, one submission, task registration and cross-kind VMID blocking;
- source-smoke assertions for the LXC gateway, unprivileged flag, UI confirmation and permission contract.

## Remaining gates

This does not certify production LXC creation. Before widening scope or calling the feature production-ready, retain the existing gates for disposable PVE 8.4 and 9.2 fixtures covering ACL inheritance, storage plugins, template formats, quorum/VMID races, task failures and network faults, plus physical Android confirmation/accessibility/network-transition testing.

Privileged containers, custom rootfs sizing, networking, passwords/SSH keys, start-after-create, pools, HA, restore, advanced features/mounts, migration and richer provisioning remain gated.
