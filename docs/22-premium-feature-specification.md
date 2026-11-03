# Premium Feature Specification and Prioritization
Status: **feature hypotheses and delivery requirements**, not release promises. Feature IDs in [premium-feature-catalog.csv](premium-feature-catalog.csv) are normative; this document specifies cross-feature behaviors.

## Feature groups and acceptance outcomes
| Domain | Premium features worth building | Core outcome | Gate |
|---|---|---|---|
| Cockpit | cross-profile overview, customizable tiles, favorites, command palette, pinned incidents, activity timeline | see what matters in two taps | F0/F1 |
| Discovery | hierarchical clusters/nodes/guests, rich global search, tags, filters, saved views, resource relationships | find a resource in seconds | F0/F1 |
| Operations | typed VM/LXC power, safe bulk action planner, scheduled maintenance draft, task observability | know what changed and why | F0/F2 |
| VM/LXC | create, template, clone, resize, snapshots, migration, cloud-init, hardware config, permissions | manage workloads correctly | F1/F2 |
| Console | live QEMU graphical VNC, LXC shell with deliberate ticket/session auth; mobile keyboard | emergency access from phone | F1 after RFC |
| Performance | RRD history, comparisons, guest charts, trend bands, capacity planning, predictive risk with confidence | anticipate constraints | F1/F3 |
| Backup | PVE backup jobs, snapshot catalog, restore wizard, PBS explorer, sync/verify health | make recovery testable | F1/F4 |
| Infrastructure | node health, quorum, HA resources/rules, Ceph OSD/pool, ZFS/storage, SDN and firewall visibility | see cluster health | F1/F2 |
| Alerting | local watched thresholds, task failures, notification center, optional self-hosted relay | prioritize outages | F1/F4 |
| Access | roles, multiple identities, cert management, session hygiene, app lock, secure profile export | safe administration | F0/F2 |
| Native Android | home screen widget, quick access, biometric lock, notification deep links, offline read-only | native mobile convenience | F1/F2 |
| Insights | explain failed tasks, annotated incidents, local heuristics, optional private on-device assistant | reduce operator time | F3 |
| Ecosystem | distinct PBS/PDM connections, unified read-only summary, rich multi-site operations | scale beyond single cluster | F4 |

## Release prioritization model
Each feature is scored (1–5) for operator value, frequency, reliability, user reach, cost and security risk. Proposed weighted score: 0.30 value + 0.20 frequency + 0.20 reach + 0.15 feasibility + 0.15 confidence minus a separately displayed security-risk penalty. **Safety prerequisites override numeric rankings.** Do not conflate an easy UI with a safe backend endpoint.

## Capability gates
A feature is rendered only if ALL are true: build flag enabled; endpoint supported by specific PVE/PBS/PDM version; auth mode compatible; server permissions sufficient (best-effort preflight); online/write-safe state if mutation; required hardware/plugin present; security RFC signed off. Server-side ACL is authoritative even if preflight succeeds. Unsupported feature explanation must specify what is missing and a safe fallback.

## Behavior classes
- **Read-only:** may auto-refresh with capped rate and cached stale badge.
- **Reversible mutation:** show effect/identity, confirmation, task progress; no ambiguous retries.
- **Disruptive/destructive:** re-fetch state, confirm exact target and risk, require deliberate final gesture or typed name for deletions, verify backups/quorum and concurrency.
- **Privileged infrastructure:** use maintenance checklist, preconditions, elevated re-auth and explicit documentation of no automatic rollback.
- **Research-only:** hidden from release builds until protocol/auth/UX integration tests pass.

## Unifying interaction contract
For actions, always show: profile + node + guest kind + VMID, operation, current state and fetched time, permission hint, impact, options, confirmation, submitted UPID (if returned), log progress, final server state, recovery choices. Never quietly re-submit a timed-out mutation. Bulk action should be serialized or bounded with per-target results, not “all succeeded” after HTTP accepts.

## First premium release cut (recommended)
A polished F0 plus selected F1 essentials: rich dashboard, reliable read-only graphs, multi-cluster profiles, search, favorites, task timelines, backup status, safe power actions, dark/light theme, biometric app lock, accessible error states. Ship console, restore, migration and infrastructure edits in later gated releases rather than making them fragile prerequisites for first release.
