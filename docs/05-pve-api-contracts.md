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
| GET | `/cluster/resources` | global overview | list of nodes/guests/storage; optional `type` filter | Candidate contract; validate details |
| GET | `/nodes` | node list | node state/identifier | Candidate contract; validate details |
| GET | `/nodes/{node}/status` | node detail | CPU, memory, uptime, etc. | Candidate contract; validate details |
| GET | `/nodes/{node}/qemu` | VM inventory | QEMU list | Candidate contract; validate details |
| GET | `/nodes/{node}/qemu/{vmid}/status/current` | VM detail | current status | Candidate contract; validate details |
| POST | `/nodes/{node}/qemu/{vmid}/status/start` | start VM | task/UPID | Candidate contract; validate |
| POST | `/nodes/{node}/qemu/{vmid}/status/shutdown` | graceful shutdown VM | task/UPID | Candidate contract; validate |
| POST | `/nodes/{node}/qemu/{vmid}/status/stop` | force stop VM | task/UPID | Candidate contract; validate |
| POST | `/nodes/{node}/qemu/{vmid}/status/reboot` | guest reboot VM | task/UPID | Candidate contract; validate |
| GET | `/nodes/{node}/lxc` | container inventory | LXC list | Candidate contract; validate |
| GET | `/nodes/{node}/lxc/{vmid}/status/current` | LXC detail | current status | Candidate contract; validate |
| POST | `/nodes/{node}/lxc/{vmid}/status/start` | start LXC | task/UPID | Candidate contract; validate |
| POST | `/nodes/{node}/lxc/{vmid}/status/shutdown` | orderly shutdown LXC | task/UPID | Candidate contract; validate |
| POST | `/nodes/{node}/lxc/{vmid}/status/stop` | force stop LXC | task/UPID | Candidate contract; validate |
| POST | `/nodes/{node}/lxc/{vmid}/status/reboot` | reboot LXC | task/UPID | Candidate contract; validate |
| GET | `/nodes/{node}/tasks` | node tasks | recent task records | Candidate contract; validate |
| GET | `/nodes/{node}/tasks/{upid}/status` | task completion | running/stopped, exit status | Candidate contract; validate |
| GET | `/nodes/{node}/tasks/{upid}/log` | task log | lines/events | P1; validate |
| GET | `/nodes/{node}/storage` | storage list | storages with usage | Candidate contract; validate |

Guest resource entries may include optional `netin`, `netout`, `diskread`, and `diskwrite` cumulative byte counters. They are **not** current bytes/second; missing or malformed fields are unavailable rather than zero. Source-level parsing/display is covered by synthetic tests, while exact PVE 8.4/9.2 fixtures and lifecycle reset semantics still require validation.

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
