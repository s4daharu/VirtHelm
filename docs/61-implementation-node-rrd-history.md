# Node RRD performance history — read-only E03-01 slice

**Increment:** 2026-11-06. This source-level milestone extends the existing bounded RRD pattern from guests to nodes. It does **not** establish live PVE 9.2/8.4 compatibility, ACL completeness, physical-device performance, or production readiness.

## Scope

- Home node rows open a dedicated node detail route scoped to the current profile ID and connection generation.
- The route shows current node CPU, memory, uptime and status from the existing cluster inventory.
- Historical CPU and memory averages are loaded only after an explicit operator action.
- Supported windows are 1 hour, 24 hours and 7 days, using `GET /nodes/{node}/rrddata` with `cf=AVERAGE`.
- Selecting a different window clears the prior series but performs no request until **Load history** is pressed.
- At most 1,500 response rows are considered locally. Valid timestamped CPU fractions in 0..1 and memory ratios from non-negative `mem` with positive `maxmem` are retained; malformed rows are counted and ignored.
- Samples are sorted by timestamp and rendered with CPU/memory latest value, range, sample count and accessible chart semantics.

## Session, privacy and safety boundary

The request is GET-only. Before and after I/O, the controller requires the same active profile ID, connection generation and exact visible node name. A profile switch, reconnect or node disappearance discards the result; the open route redacts instead of continuing to show the prior profile's node details.

RRD history is held only in transient widget state. It is not written to SharedPreferences, the credential vault, the offline overview cache, logs, exports or telemetry. There is no background RRD polling, Android permission, new dependency or write endpoint.

Explicit Android default-network loss prevents a new node-history request. An observed 401 purges/hides optional offline counts and marks the current live inventory authorization state unsafe until a clean authenticated refresh. This does not broaden mutation behavior, task orchestration or GET retry policy.

## Contract evidence and verification boundary

The Proxmox node API exposes `/nodes/{node}/rrddata` for historical node statistics. Proxmox developer discussion distinguishes this averaged RRD data from the instantaneous `/nodes/{node}/status` CPU value, and Proxmox staff examples use the node RRD endpoint with a timeframe.

Automated coverage checks response parsing, exact GET path/parameters, session isolation, explicit-load behavior, timeframe invalidation and route redaction.

**Still open:** sanitized PVE 9.2 and 8.4 node RRD fixtures confirming field availability, ACL behavior, resolution/missing-point semantics and cluster forwarding; physical Android TalkBack, large-text and performance evidence; and broader storage/capacity charts.
