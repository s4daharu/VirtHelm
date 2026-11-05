# Guest performance history — bounded read-only RRD charts

**Increment:** 2026-11-06. This source-level milestone advances the planned M2/M3 read cockpit with on-demand guest performance history. It does **not** establish live PVE 9.2/8.4 compatibility, physical Android validation, or release certification.

## Scope

- Guest detail can explicitly load average Proxmox RRD history for **1 hour**, **24 hours**, or **7 days**.
- The gateway performs only `GET /nodes/{node}/{qemu|lxc}/{vmid}/rrddata` with the selected `timeframe` and fixed `cf=AVERAGE`. No mutation endpoint, task submission, automatic polling, or background fetch is introduced.
- The first chart slice is intentionally limited to CPU and memory utilization fractions. Network/disk RRD rate semantics remain deferred until versioned PVE fixtures confirm exact field units and reset behavior.
- Responses are bounded locally to 1,500 rows. Valid samples are sorted by timestamp; malformed rows are ignored and counted. CPU must be finite and between 0 and 1. Memory requires finite non-negative `mem` and positive `maxmem`, with `mem <= maxmem`.
- History is transient route state only. It is not added to controller persistence, SharedPreferences, secure storage, offline overview cache, logs, telemetry, exports, or task data.

## Session isolation and privacy

The guest route already captures profile ID plus connection generation. RRD reads reuse that boundary: the exact node/type/VMID must still exist in the active live inventory before the request and after it completes. Profile switches, reconnects, guest disappearance, or stale generations discard the result. A 401 follows the existing authentication-loss cache clearing path.

Loaded metric history is removed from view when the connection changes. Charts expose a text summary (latest value, range, and sample count) through normal text and semantics so the visual line is not the sole representation.

## Contract basis and verification boundary

The Proxmox API/source family documents guest RRD data as a read-only endpoint with a timeframe and consolidation function. This implementation uses only the common `hour`, `day`, and `week` windows and `AVERAGE`, avoiding newer/version-specific options.

Automated coverage includes conservative sample parsing, exact GET path/query parameters, controller session isolation, explicit-load behavior, no request on timeframe selection alone, malformed-count display, chart text alternatives, and profile-switch redaction. The repository's pinned formatter, analyzer, Flutter suite, Android hardening checks, and debug APK build remain the exact-head merge gate.

**Still open:** sanitized PVE 9.2 and 8.4 RRD payload/ACL fixtures for QEMU and LXC, missing-series behavior, timestamp/resolution checks, physical Android TalkBack/large-text/performance review, and independent security/release validation.
