# Monitoring, Alerting, Capacity and Incident Intelligence
This is a modular design; it does not promise server push or always-on polling without a relay.

## Monitoring hierarchy
| Source | Candidate signals | Ground truth |
|---|---|---|
| PVE cluster | quorum, node online state, guest inventory, task failures | PVE REST per cluster |
| Nodes | CPU, memory, swap, uptime, disk and load where available, syslog tasks | node endpoint/RRD, versioned |
| QEMU/LXC | CPU, allocated/used memory, disk/network rate where available, VM run state | guest and RRD/agent endpoints |
| HA/Ceph | HA resource status, Ceph health and OSD/pool warnings | module-specific endpoints |
| Storage | used/total, available pool capacity, latency when exposed, backups | PVE/PBS appropriate service |
| Security | login/token expiry/certificate expiry, updates/subscription status | explicitly queried sources |

Different interval/bucketing and availability must be normalized without false precision. Always show units, window, missing samples, timezone, collector origin, collection timestamp, rate vs total, and whether data is estimated.

## Premium visualizations
- 1h/24h/7d/30d graphs with axis labels and drill-down from top cards.
- Compare guests/nodes on same units and timeframe; avoid mixing rate, percent, and absolute.
- Capacity runway (linear/robust trend with seasonal uncertainty, excluding missing/stale data) displayed as **estimate**.
- Top resource consumers and anomaly candidates with simple disclosed heuristics.
- Incident timeline correlated with tasks, state changes and alerts; show data-source gaps.
- Post-incident non-secret export bundle with system time, redacted task IDs and diagnostics.
- Local saved thresholds for individual workloads, groups and site totals; exclude non-accessible resources.

## Alert engines — accurate behavior contract
**Mode A — foreground:** immediate in-app badge and optional notifications only while polling or receiving data. Works without external backend.
**Mode B — Android scheduled:** opted-in WorkManager periodic checks when network/VPN and OS conditions permit; **minimum 15-minute repeat interval and execution is not exact**. Not an SLA, not suitable for critical paging. Never use a permanent hidden foreground service to circumvent Android policies.
**Mode C — optional self-hosted alert relay (future):** owner-hosted server receives events/polls securely, sends alert notifications via an explicitly consented push or webhook integration. Only mode C could aim for low-latency alerting while app is closed; design separate key rotation, registration, disable, auditing and operational maintenance. No mandatory vendor cloud.

## Alert rule model
Rule(id, profileId, resourceSelector, metric, comparator, threshold, window, consecutiveSamples, severity, quietHours, cooldown, dedupKey, locale, enabled). State machine OK -> Pending -> Firing -> Acknowledged -> Resolved with hysteresis and per-profile dedup. Suppress repeats during known maintenance, stale data, permission errors and missing samples; **unknown is not healthy**. Alert payload redacted: alias, severity, generic resource display, timestamp; no secrets or customer-sensitive guest names on lock screen by default.

## Current bounded ALERT-02 triage slice (0.1.49)
The Android foreground inbox now supports session-local needs-review/acknowledged
and earlier-signal views. Acknowledgement is strictly a local annotation and
does not affect severity, server tasks, rule firing or health status. Only a
complete authenticated foreground refresh can move a missing observation to
the earlier list; failed or partial reads do not prove resolution. The history
is capped at 40 entries in memory and is cleared on reconnect/profile change.
This is not the full persisted alert state machine described above. Quiet hours,
cooldown, cross-session correlation, durable acknowledgement, notifications,
background checks and relay integration remain proposed.

## Mobile triage workflow follow-up (0.1.50)

The foreground inbox adds source chips, an on-device text query against
currently loaded incident details and an explicit confirmation to acknowledge
only the filtered needs-review keys. Every batch rechecks the active profile,
connection generation and current incident identities. Other incidents,
underlying severities and badges are unchanged. Mobile cards present severity
at a readable theme-scaled size. This introduces no network endpoint,
persistence, background notification or server acknowledgement.

## Intelligence without unsafe automation
F3 “Insights” are deterministic, explainable, local by default: suspicious CPU plateau, insufficient free space, frequent restart, failed task cluster, missing recent backup, irregular node load, capacity risk. A recommendation card includes: evidence and date range, uncertainty, why this matters, docs link, and **Review action** (never execute). Optional LLM/on-device natural-language interface is research-gated; no auto-remediation, no secret sharing, no cloud upload without explicit and revocable consent.

## Performance and power budgets
Foreground overview adaptively refreshes at proposed 15–30s by default only on visible screens; lazy-fetch detail/graphs, limit parallel requests, pause on background, coarse WorkManager checks only by opt-in. For 200 guests avoid per-guest polling waterfall. Record data transfer, battery and request counts per 15-minute sample in lab tests.

## Acceptance tests
A1: no false “resolved” on lost connection. A2: missed background check does not appear as continuous coverage. A3: alert rule dedup/silence/tz/DST works. A4: revoked token stops polling and deletes registration if relay. A5: no guest details exposed in notifications when privacy mode active. A6: anomaly results have explainable data and never auto-submit PVE writes.


## Foreground notification policy follow-up (0.1.52)

Mode A now includes an explicit opt-in foreground Android delivery path for new
durable incident occurrences. Profile-scoped quiet hours and cooldown suppress
only notification delivery; they do not alter the incident builder, current
health counters, acknowledgement state, durable history or any mutation guard.
The native notification payload is generic and excludes profile/resource names,
VMIDs, UPIDs and task logs. Android 13+ permission is requested only when the
operator enables the feature. No WorkManager, alarm, foreground service,
background credential read or additional PVE endpoint is introduced.

## Android scheduled node-state follow-up (0.1.53)

Mode B now has a deliberately bounded first implementation slice. For an
explicitly opted-in certificate-verified profile, Android WorkManager may run
one GET-only node-state check when its connected-network constraint and OS
scheduling conditions permit. Requested intervals begin at 15 minutes and are
inexact. The UI exposes last-attempt, last-complete and outcome evidence so a
missed or incomplete run is not presented as continuous coverage.

The worker uses a separate AES-256-GCM Android-Keystore-encrypted token copy
because the Flutter credential vault is not available to a stopped Dart
isolate. Profile edit/delete cleanup is owned by AppController. Redirects are
disabled, reads are bounded, no immediate retry is requested, and scheduled
notifications are generic and private. Profiles using the insecure TLS
exception cannot enable this mode.

This does not implement full Mode B parity: background failed-task/threshold
rules, authoritative correlation, cross-mode notification deduplication and
relay delivery remain gated. The feature remains best-effort Android
scheduling, never critical paging or 24/7 monitoring.

## Notification lock-screen privacy follow-up (0.1.54)

ALERT-010 adds one device-wide privacy choice shared by Mode A and Mode B.
The default requests Android secret visibility so no part of an incident
notification is revealed on a secure lock screen. Operators may instead allow
the already-generic VirtHelm alert with private visibility. No public mode is
exposed, and payloads still exclude infrastructure identifiers, task details,
credentials and raw responses.

The preference is synchronized into native Android storage for WorkManager.
Unknown or missing values fail closed to hidden. Android and operator channel
settings remain authoritative and may further restrict lock-screen display.
Resource-specific notification deep links and any unlock bypass remain gated.
