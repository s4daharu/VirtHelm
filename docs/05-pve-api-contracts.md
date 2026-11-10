# Proxmox VE REST API Contract and Endpoint Catalog

**Scope:** PVE, *not* PBS/PDM. **Reference API viewer:** https://pve.proxmox.com/pve-docs/api-viewer/ . Source code/docs references appear in [14-research-sources.md](14-research-sources.md).

## 1. Verified protocol baselines
- HTTPS daemon: `pveproxy` on TCP 8006; cluster requests can be forwarded across nodes.
- JSON API prefix: `/api2/json`.
- API token header: `Authorization: PVEAPIToken=USER@REALM!TOKENID=SECRET` (the final `=` belongs between token name and secret; retain literal `!`).
- User session uses `PVEAuthCookie=<ticket>` and CSRF token for modifying requests; do **not** apply CSRF to API token auth. Exact ticket/2FA handshake requires versioned validation before P1.
- Common success envelope is `{ "data": ... }`. A write may produce a `UPID:...` in `data` indicating an **asynchronous task**, not the operation's success.
- API token privileges are intersected with owning user permissions when privilege separation is enabled. **Console endpoints are exceptions to token access.**

## 2. MVP endpoints (check specific parameter schema on 9.2 and 8.4 before coding)
| Method | Endpoint (relative to `/api2/json`) | Feature | Expected concept | Status |
|---|---|---|---|---|
| GET | `/version` | connect test | `version`, `release` fields | Officially documented, live fixture pending |
| GET | `/access/permissions` with `path=/vms/{vmid}` | exact guest permission hints | map of ACL path -> effective privilege -> propagation flag | Upstream access-control source confirmed; live 8.4/9.2 fixture pending |
| GET | `/access/permissions` with `path=/storage/{storage}` | backup-storage permission preflight | effective storage privileges including `Datastore.AllocateSpace` | Upstream access-control/vzdump contract reviewed; live 8.4/9.2 fixture pending |
| GET | `/cluster/resources` | global overview | list of nodes/guests/storage; optional `type` filter | Candidate contract; validate details |
| GET | `/cluster/nextid` with optional `vmid={newid}` | provisioning VMID suggestion/collision preflight | next free VMID or explicit free-VMID validation | Upstream create/clone preflight contract reviewed; live 8.4/9.2 fixture pending |
| GET | `/nodes` | node list | node state/identifier | Candidate contract; validate details |
| GET | `/nodes/{node}/status` | node detail | CPU, memory, uptime, etc. | Candidate contract; validate details |
| GET | `/nodes/{node}/rrddata` | node performance history | timestamped CPU/memory averages with `timeframe` + `cf` | Source-confirmed read family; live 8.4/9.2 fixtures pending |
| GET | `/nodes/{node}/qemu` | VM inventory | QEMU list | Candidate contract; validate details |
| GET | `/nodes/{node}/qemu/{vmid}/status/current` | VM detail | current status | Candidate contract; validate details |
| POST | `/nodes/{node}/qemu` | guarded empty QEMU VM create | `vmid`, `name`, `cores`, `memory`, `onboot`; task/UPID | Upstream QEMU create source confirmed; live 8.4/9.2 mutation fixture pending |
| GET | `/nodes/{node}/{qemu|lxc}/{vmid}/rrddata` | guest performance history | timestamped CPU/memory averages with `timeframe` + `cf` | Source-confirmed read family; live 8.4/9.2 fixtures pending |
| POST | `/nodes/{node}/qemu/{vmid}/status/start` | start VM | task/UPID | Candidate contract; validate |
| POST | `/nodes/{node}/qemu/{vmid}/status/shutdown` | graceful shutdown VM | task/UPID | Candidate contract; validate |
| POST | `/nodes/{node}/qemu/{vmid}/status/stop` | force stop VM | task/UPID | Candidate contract; validate |
| POST | `/nodes/{node}/qemu/{vmid}/status/reboot` | guest reboot VM | task/UPID | Candidate contract; validate |
| POST | `/nodes/{node}/qemu/{vmid}/clone` | guarded full template clone | `newid`, `full=1`, `name`; task/UPID | Upstream QEMU source confirmed; live 8.4/9.2 mutation fixture pending |
| GET | `/nodes/{node}/qemu/{vmid}/migrate` with `target={node}` | guarded QEMU migration preflight | running state, allowed targets, local disks/resources and blockers | Upstream QEMU source confirmed; live 8.4/9.2 fixture pending |
| POST | `/nodes/{node}/qemu/{vmid}/migrate` | guarded same-cluster QEMU migration | `target` and `online=1` only for a running VM; task/UPID | Upstream QEMU source confirmed; live 8.4/9.2 mutation fixture pending |
| GET | `/nodes/{node}/qemu/{vmid}/snapshot` | QEMU snapshot inventory | bounded snapshot metadata | Source-reviewed read contract; live 8.4/9.2 fixture pending |
| POST | `/nodes/{node}/qemu/{vmid}/snapshot` | guarded create-only QEMU snapshot | `snapname` only; qmsnapshot task/UPID | Upstream snapshot contract reviewed; live 8.4/9.2 mutation fixture pending |
| DELETE | `/nodes/{node}/qemu/{vmid}` | guarded stopped-QEMU deletion | no optional destructive knobs; task/UPID | Upstream QEMU source confirms VM.Allocate + qmdestroy; live 8.4/9.2 mutation fixture pending |
| GET | `/nodes/{node}/lxc` | container inventory | LXC list | Candidate contract; validate |
| GET | `/nodes/{node}/lxc/{vmid}/status/current` | LXC detail | current status | Candidate contract; validate |
| POST | `/nodes/{node}/lxc/{vmid}/status/start` | start LXC | task/UPID | Candidate contract; validate |
| POST | `/nodes/{node}/lxc/{vmid}/status/shutdown` | orderly shutdown LXC | task/UPID | Candidate contract; validate |
| POST | `/nodes/{node}/lxc/{vmid}/status/stop` | force stop LXC | task/UPID | Candidate contract; validate |
| POST | `/nodes/{node}/lxc/{vmid}/status/reboot` | reboot LXC | task/UPID | Candidate contract; validate |
| POST | `/nodes/{node}/lxc/{vmid}/clone` | guarded full template clone | `newid`, `full=1`, `hostname`; task/UPID | Upstream LXC source confirmed; live 8.4/9.2 mutation fixture pending |
| GET | `/nodes/{node}/lxc/{vmid}/migrate` with `target={node}` | guarded LXC migration preflight | running state, allowed targets and HA blockers | Upstream LXC source confirmed; live 8.4/9.2 fixture pending |
| POST | `/nodes/{node}/lxc/{vmid}/migrate` | guarded same-cluster LXC migration | `target`; running CT adds `restart=1`; task/UPID | Upstream LXC source confirmed; live 8.4/9.2 mutation fixture pending |
| GET | `/nodes/{node}/lxc/{vmid}/snapshot` | LXC snapshot inventory | bounded snapshot metadata | Source-reviewed read contract; live 8.4/9.2 fixture pending |
| POST | `/nodes/{node}/lxc/{vmid}/snapshot` | guarded create-only LXC snapshot | `snapname` only; vzsnapshot task/UPID | Upstream snapshot contract reviewed; live 8.4/9.2 mutation fixture pending |
| DELETE | `/nodes/{node}/lxc/{vmid}` | guarded stopped-LXC deletion | no optional destructive knobs; task/UPID | Upstream LXC source confirms VM.Allocate + vzdestroy; live 8.4/9.2 mutation fixture pending |
| GET | `/nodes/{node}/tasks` | node tasks | recent task records | Candidate contract; validate |
| GET | `/nodes/{node}/tasks/{upid}/status` | task completion | running/stopped, exit status | Candidate contract; validate |
| GET | `/nodes/{node}/tasks/{upid}/log` | task log | lines/events | P1; validate |
| GET | `/nodes/{node}/storage` | storage list | storages with usage/content flags | Candidate contract; validate |
| GET | `/nodes/{node}/storage/{storage}/content` with `content=backup&vmid={vmid}` | exact-guest backup archive visibility | bounded backup volume metadata | Storage-content/VMID contract documented; live 8.4/9.2 backend fixture pending |
| POST | `/nodes/{node}/vzdump` | guarded one-off guest backup | one VMID, selected storage, `mode=snapshot`; vzdump task/UPID | Upstream vzdump source/permissions reviewed; live 8.4/9.2 mutation fixture pending |
| GET | `/nodes/{node}/storage/{storage}/rrddata` | storage capacity history | timestamped used/total capacity with `timeframe` + `cf` | Source-confirmed read family; live 8.4/9.2 fixtures pending |

Guest, node and storage performance history use only `hour`, `day`, and `week` timeframes with `cf=AVERAGE` in the source implementation. Node history currently retains CPU and memory ratios only. Storage history retains non-negative used bytes and positive total bytes, and computes a usage ratio only when used does not exceed total. Broader RRD fields remain deferred until versioned fixtures establish units and missing-point behavior. Samples are treated as provisional until sanitized PVE 9.2/8.4 fixtures confirm field availability, units, ACL behavior, timestamp resolution, and missing-point semantics.

Guest resource entries may also expose optional `tags` and `pool` discovery metadata. Upstream source history confirms guest tags on `/cluster/resources`; this client treats both fields as display/filter metadata only and still requires sanitized PVE 8.4/9.2 fixtures for exact availability, ACL, case-sensitivity and pool-shape behavior. Missing or malformed optional metadata is unavailable rather than a malformed guest identity.\n\nGuest resource entries may include optional `netin`, `netout`, `diskread`, and `diskwrite` cumulative byte counters. They are **not** current bytes/second; missing or malformed fields are unavailable rather than zero. Source-level parsing/display is covered by synthetic tests, while exact PVE 8.4/9.2 fixtures and lifecycle reset semantics still require validation.

For the guarded empty-QEMU create slice, upstream QEMU source confirms `POST /nodes/{node}/qemu`, `VM.Allocate` on the destination, and option-specific `VM.Config.CPU`, `VM.Config.Memory`, and `VM.Config.Options` checks. VirtHelm sends no disk, network, storage, media, pool, HA, restore or start fields, so this slice does not request `Datastore.AllocateSpace`, `SDN.Use`, or `VM.PowerMgmt`. The server remains authoritative for quorum, VMID uniqueness and all request validation.

For the guarded LXC create slice, current upstream LXC/storage source confirms `POST /nodes/{node}/lxc`, required `ostemplate`, active `rootdir` storage, default unprivileged creation, and the `vzcreate` worker. VirtHelm discovers existing `vztmpl` content, sends `unprivileged=1`, and omits an explicit `rootfs`, allowing Proxmox's reviewed default 4 GiB rootfs allocation on the selected storage. Preflight hints require destination `VM.Allocate`, `VM.Config.CPU`, `VM.Config.Memory`, `VM.Config.Network` (hostname), `VM.Config.Options` (onboot), rootfs-storage `Datastore.AllocateSpace`, and readable template storage (`Datastore.Audit` or `Datastore.AllocateSpace`). Privileged mode, custom rootfs sizing, passwords/SSH keys, networking, pool/HA, restore and start-after-create remain gated; live PVE 8.4/9.2 fixtures remain required.

For the guarded template-clone slice, current upstream QEMU/LXC source confirms the clone endpoint families and source `VM.Clone` plus destination `VM.Allocate` checks. QEMU additionally documents datastore allocation and SDN-use requirements where applicable. VirtHelm therefore treats its source/destination permission probes as partial preflight only: it sends a full same-node clone with no explicit storage/target/pool override, never retries the POST, and lets Proxmox remain final authority for datastore/network authorization. Live PVE 8.4/9.2 clone fixtures remain required.

For the guarded migration slice, current upstream QEMU and LXC sources confirm `VM.Migrate` on the exact guest path, a GET precondition check and a POST on `/nodes/{node}/{qemu|lxc}/{vmid}/migrate`. QEMU preflight exposes allowed targets plus local disks/resources; VirtHelm refuses this first slice if either local category is present and therefore sends none of the local-disk, target-storage, force, migration-network or migration-type knobs. A running QEMU VM adds only `online=1`. A running LXC container uses `restart=1` because the reviewed LXC path does not provide live migration; stopped guests send only `target`. Normal workers are `qmigrate`/`vzmigrate`, while HA-managed guests can return `hamigrate`. Every mutation remains exactly-once with uncertain-outcome lockout, and live PVE 8.4/9.2 migration/HA/storage fixtures remain required.

For the guarded backup-start slice, the reviewed vzdump contract uses `POST /nodes/{node}/vzdump` for one exact VMID. VirtHelm revalidates the unchanged guest, requires `VM.Backup` on `/vms/{vmid}`, re-reads node storage and requires the selected target to remain enabled/active with `backup` content, then requires `Datastore.AllocateSpace` on `/storage/{storage}`. It sends only `vmid`, `storage` and `mode=snapshot`, accepts only an exact-node/exact-VMID `vzdump` UPID, and never retries the mutation. Pruning/retention, hooks/scripts, fleecing, bandwidth/performance/ionice tuning, archive integrity verification and restore remain gated; live PVE 8.4/9.2 backup/storage/ACL/fault fixtures are required.

For exact-guest backup archive visibility, VirtHelm uses the existing storage-content GET family with `content=backup` plus the exact VMID. It accepts only volume identifiers that also match the current guest type (`vzdump-qemu`/`backup/vm` for QEMU or `vzdump-lxc`/`backup/ct` for LXC), caps results locally, retains only reviewed metadata, and discards results if the guest/session/storage changes. This proves only current PVE storage visibility; checksum/integrity verification, PBS verification state and restore remain separate gated capabilities. Live PVE 8.4/9.2 directory/NFS/CIFS/PBS-backed content schemas and ACL behavior remain required.

The BKP-009 confidence card adds no endpoint. It is a local classification over the exact-guest archive read plus recent `vzdump` task history. The strongest state is deliberately `Partial evidence`; task success cannot substitute for archive presence, and archive presence cannot substitute for integrity verification or a tested restore. PBS verification remains a separate PBS capability and is not inferred from PVE storage metadata.

BKP-007/BKP-008 restore planning in 0.1.45 also adds no mutation endpoint. The bounded same-node alternate-VMID preflight composes existing GET-only contracts: fresh cluster inventory, exact archive re-read through storage content, node storage status, destination `/vms/{vmid}` effective permissions, and `/storage/{storage}` effective permissions. It blocks occupied VMIDs, incomplete storage reads, missing/inactive/type-incompatible storage, stale archives, and absent `VM.Allocate`/`Datastore.AllocateSpace` hints. Archive size is not treated as a restored-capacity estimate. Actual QEMU/LXC restore endpoints, overwrite semantics, worker/UPID contracts and uncertain-outcome handling remain unimplemented and require separate source/live review.

For the guarded snapshot-creation slice, current QEMU/LXC contracts use `POST /nodes/{node}/{qemu|lxc}/{vmid}/snapshot` with `VM.Snapshot` on the exact guest path. VirtHelm first re-reads a clean unchanged guest inventory, requires a complete on-demand snapshot list with no exact name collision, sends only `snapname`, and never requests QEMU `vmstate`. Returned tasks are restricted to `qmsnapshot`/`vzsnapshot` with exact source-node and VMID matching. Rollback/delete, description, RAM-state capture and backup claims remain gated; live PVE 8.4/9.2 storage/backend/ACL/fault fixtures are required.

For the guarded deletion slice, current upstream QEMU/LXC contracts use `DELETE /nodes/{node}/{qemu|lxc}/{vmid}`, require `VM.Allocate` on the exact guest path and return `qmdestroy`/`vzdestroy` task workers. VirtHelm requires the guest to remain stopped, re-reads a clean exact inventory, probes the privilege immediately before submission, sends no `skiplock`, `purge`, unreferenced-disk or other optional destructive parameters, and never retries the DELETE. The confirmation explicitly warns that used/owned volumes and snapshots may be destroyed; recovery-backup verification remains an operator gate, not a claim inferred from snapshot/task metadata. Live PVE 8.4/9.2 deletion/HA/lock/storage fixtures remain required.

For guest permission hints, VirtHelm requests only the authenticated token's own exact `/vms/{vmid}` path. Upstream access-control source explicitly allows a user/token to dump its own effective permissions. Presence of a privilege at the exact path is treated as the grant; the returned boolean/0/1 value is a propagation flag and is not used as an allow/deny value. The result remains a presentation hint only and never replaces operation-specific server authorization or live mutation preflight. Live 8.4/9.2 token/ACL fixtures are still required.

`Candidate contract` means endpoint family is known from the PVE API/source ecosystem but exact methods, optional params and return schemas were **not independently live-tested** for both 8.4 and 9.2 when this package was prepared. Treat this table as a work queue, not a frozen/generated OpenAPI schema. API viewer on installed target PVE is definitive for that server.

## 3. Response examples (illustrative only; **not** captures)
```json
{ "data": { "version": "9.2.x", "release": "9.2" } }
```
```json
{ "data": [
  { "type":"qemu", "vmid":101, "node":"pve1", "name":"demo", "status":"running", "cpu":0.1, "mem":536870912, "maxmem":2147483648 }
] }
```
```json
{ "data": "UPID:pve1:00000000:00000000:00000000:qmstart:101:example@pve:" }
```
**These are synthetic illustrative shape examples only.** Preserve unknown fields and correctly handle optional, null, int/double numeric variance and missing `data`.

## 4. Task state machine
`idle -> submitting -> submitted(UPID) -> polling -> terminal(success | failure | unknown)`.
- On HTTP network failure **after** POST write, status is *unknown*, not safe to retry. Query guest/task history, ask user to refresh.
- For task status evaluate both `status` terminal value and `exitstatus`; `stopped` **alone does not mean success**.
- Per-node UPID task routing matters; persist node alongside task ID; do not display a guessed progress percentage.
- Error body may include validation details: show safe message, keep technical details in redacted diagnostics.

## 5. Type-specific behavior and permissions
- QEMU and LXC have distinct endpoint prefixes and supported action semantics; no false common lifecycle assumption.
- Do not hardcode one administrator role as requirement. Use ACL-aware errors. Token privileges may be limited and not all objects may be returned.
- Do not use undocumented endpoint aliases; URL-encode node names and UPIDs with segment-aware encoding.
- `cluster/resources` may expose a common inventory, but use guest type+node+vmid for action addressing; never assume guest name is unique.

## 6. Integrator checklist
For each endpoint: record full PVE version, method, path, params (including POST form vs JSON encoding), auth mode, privilege path, success JSON with field nullability, 401/403 body, asynchronous result, rate/timeout behavior and fixture hash. Block releasing a mutation until a non-production PVE integration test proves it. See CSV inventory and verification matrix.
