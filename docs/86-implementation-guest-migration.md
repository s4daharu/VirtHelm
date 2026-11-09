# 86. Guarded guest migration implementation

Status: **source-level implemented; live PVE 8.4/9.2 mutation and physical-device gates remain open**  
Date: 2026-11-10

## Scope

This increment delivers the first bounded GUEST-06 migration workflow for existing QEMU VMs and LXC containers inside the active Proxmox VE cluster.

The workflow is intentionally narrow:

- one exact guest at a time;
- one different, currently online destination node;
- typed source VMID confirmation before submission;
- current-token `VM.Migrate` capability hint;
- Proxmox's own GET migration-precondition endpoint immediately before submission;
- exactly one migration POST and UPID tracking;
- no automatic retry after a mutation attempt.

It does **not** expose force migration, migration-network/type tuning, bandwidth controls, target-storage remapping, cross-cluster migration, bulk migration or local-device overrides.

## Upstream contracts reviewed

Current upstream Proxmox sources confirm the same path family for preflight and mutation:

### QEMU

- `GET /nodes/{node}/qemu/{vmid}/migrate?target={node}`
  - requires `VM.Migrate`;
  - returns current running state, allowed/not-allowed target nodes, local disks, local resources, mapped-resource details and HA motion information.
- `POST /nodes/{node}/qemu/{vmid}/migrate`
  - requires `VM.Migrate`;
  - a running VM requires `online=1`;
  - normal tasks use `qmigrate`; HA-managed guests can return `hamigrate`.

VirtHelm deliberately refuses this first QEMU slice when server preflight reports any local disks or local host resources. It therefore does not expose `with-local-disks`, `targetstorage`, `force`, `migration_type`, `migration_network` or conntrack options.

### LXC

- `GET /nodes/{node}/lxc/{vmid}/migrate?target={node}`
  - requires `VM.Migrate`;
  - returns current running state plus allowed/not-allowed target nodes and HA motion information.
- `POST /nodes/{node}/lxc/{vmid}/migrate`
  - requires `VM.Migrate`;
  - a running container requires either online or restart migration;
  - normal tasks use `vzmigrate`; HA-managed containers can return `hamigrate`.

VirtHelm uses **restart migration** for a running LXC container rather than representing it as live migration. The confirmation UI explicitly warns that downtime is expected.

## Preflight and mutation safety

Before the one POST, the controller revalidates:

1. originating profile and connection generation;
2. foreground/default-network availability;
3. a clean, unchanged current inventory;
4. exact source kind/node/VMID identity and non-template state;
5. source state remains the same running/stopped state reviewed by the operator;
6. destination node still exists exactly once and is online;
7. the current token reports `VM.Migrate` for the source guest;
8. Proxmox's migration-precondition GET cleanly allows the selected target;
9. for QEMU, the preflight reports no local disks and no local host resources.

The guest key and cluster-wide VMID key are reserved synchronously before asynchronous preflight. That prevents a concurrent power action, create, clone or second migration for the same VMID through the current session.

After those checks VirtHelm performs exactly one migration POST. Any ambiguous POST/result failure becomes an uncertain-operation lockout rather than a retry opportunity. Returned UPIDs are checked against the source node, source VMID and expected worker family (`qmigrate`/`vzmigrate` or `hamigrate`). Existing task polling keeps the operation locked through terminal outcome and releases it only after a later authoritative inventory refresh reconciles state.

## User experience

Non-template guest details now expose a migration action beside the existing power controls when at least one other online node is visible.

The flow:

1. choose an online destination node;
2. review source → destination and type-specific impact;
3. type the source VMID;
4. submit the guarded migration;
5. follow final state through Tasks.

For a running QEMU VM the UI explains that VirtHelm requests live migration only after the bounded shared-storage/no-local-resource preflight. For a running LXC container it explains restart migration and expected downtime.

## Verification added

Synthetic coverage now checks:

- QEMU and LXC precondition response parsing, including their different allowed-node field names;
- QEMU GET preflight plus exactly one live-migration POST;
- running-LXC restart payload and absence of live/storage/force knobs;
- strict migration UPID worker validation and ambiguous-result classification;
- controller-level `VM.Migrate` enforcement;
- QEMU local-disk/local-resource rejection before POST;
- exact task registration and guest/VMID locking;
- ambiguous migration POST lockout that survives later inventory refresh;
- source-smoke assertions for the gateway, controller and migration UI.

## Remaining gates

This is not production certification. Disposable PVE 8.4 and 9.2 testing is still required for shared/local storage combinations, HA-managed guests, ACL inheritance, restricted API tokens, QEMU live migration, stopped/offline migration, LXC restart migration, task failures and network interruption after POST.

Physical Android validation remains required for typed confirmation, TalkBack, large text, route/profile changes, Wi-Fi/VPN loss and task-state reconciliation.

Storage remapping, migration networks, bandwidth controls, local-disk transfer, force/root-only overrides, bulk/cross-cluster migration and richer migration planning remain gated.
