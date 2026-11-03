# Android Mobile UX / Information Architecture

## Navigation
A single phone-width Material 3 app shell uses: bottom navigation **Overview**, **Guests**, **Tasks**, **Settings**. Overview → Node detail and storage; Guests → Guest detail → Action confirmation → Task detail; Settings → Connections → Add/Edit/Test Profile. Display active cluster prominently in the top bar; switch via explicit selector; never mix resources from different clusters.

## Proposed routes
`/onboarding`, `/connections`, `/connections/new`, `/connections/:id`, `/overview`, `/nodes/:node`, `/guests`, `/guests/:type/:node/:vmid`, `/tasks`, `/tasks/:node/:upid`, `/storage`, `/settings`.

Route params must be URL-encoded, and displayed identifiers validated before API composition. Route to blocked resources goes to permission-aware error screen, not an ambiguous blank UI.

## Critical flows
**First launch:** short value proposition → Add connection → URL validation (`https://hostname:8006`) → choose auth mode (MVP token) → server certificate verification → test `/version` and restricted `/cluster/resources` → success/error → store profile → overview. Test connection may succeed for `/version` but fail inventory due to privilege; report partial authorization explicitly.

**Start/stop:** select guest → inspect running state and node → select action → confirm (prominent guest ID, exact cluster and node) → disable repeated submit → POST → receive UPID → poll `/nodes/{node}/tasks/{upid}/status` → show task terminal and refresh guest → reconcile stale UI.

**Switch:** stop active polling and pending requests → select profile → clear in-memory PVE ticket/token from previous connection if appropriate → load isolated snapshots → fetch new overview.

## Screens and components
| Screen | Content | Empty / error / loading behavior |
|---|---|---|
| Overview | Cluster selector, online node count, running guests, alerts about stale sync | skeleton, “permission insufficient”, offline + last seen |
| Guests | tabs All/VMs/Containers, search/sort and status chips | access denied, zero resources, offline states distinct |
| Guest detail | identity, state, resources, actions, task context | missing metrics gracefully, dangerous actions confirmed |
| Tasks | async task progress, failed result reason, recent history | no tasks / no task permission, filtered views |
| Connections | named URLs and last health; add and remove | TLS error includes safe steps, never “continue insecurely” |
| Settings | light/dark/system, refresh, telemetry OFF by default | privacy and security explanations |

## UI conventions
- Green/gray/red colors supplemented with `Running`/`Stopped`/`Error` text and icons.
- Use logical pixel responsive layouts optimized for 320–480dp phone widths, portrait + optional phone landscape. Don't build tablet, desktop or web UX.
- Hide secrets behind obscured inputs; paste support may be allowed but do not copy credentials into diagnostics.
- Make force-stop copy distinct from orderly shutdown: “Immediately stops the guest; unsaved data may be lost.”
- Screen-reader semantic labels include guest node+VMID, action type, cluster, and confirmation.
- If 2FA or certificate enrollment requires several steps, use explicit wizard screens; do not silently weaken security.
