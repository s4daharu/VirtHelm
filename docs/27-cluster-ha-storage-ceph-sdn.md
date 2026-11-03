# Pro Infrastructure — Node, Cluster, HA, Ceph, Storage and SDN
These are **advanced premium plans**, not grants of administrative rights or validated endpoint support.

## Cluster overview
Read cluster membership, node state, quorum warnings, HA resources, resource pressure, jobs and policy summary. Prefer visual cluster health with unknown states over a fake single health score. **Quorum/HA semantics are complicated:** if uncertain do not recommend a write.

## PVE 9.2 awareness
Official 9.2 (2026-05-21) adds dynamic load balancing, HA manager disarm/arm maintenance, custom CPU model management and SDN fabrics (WireGuard/BGP), among other updates. VirtHelm may show **read-only exposure first**, with mutations only after versioned schema + lab + review. Never present these as available on 8.4 by assumption.

## Operations by level
| Area | Read-only F1/F2 | Proposed guarded F2+ actions | Impact and gate |
|---|---|---|---|
| Node | status, logs/tasks, disks/storage, services, packages, certificates, update status | reboot, service restart, package update, shutdown | R3: quorum/HA & maintenance window |
| HA | resources, groups/rules, node membership, health/CRM status | enable/disable resource, migration, disarm/arm (9.2) | R3/R4: fencing data loss danger |
| Ceph | health, PG/OSD status, pools, cluster flags, latency/capacity where exposed | manage OSD, CRUSH, pools, flags | R4: data availability and recoverability |
| Storage | available space, storage types, ZFS pools, volumes, backup stores | add/edit storage, disk resize, scrub/trim | R2/R4: irreversible volume changes |
| SDN/network | zones, VNets, subnets, firewall summaries, interfaces, routes | SDN edits, firewall rule changes | R4: may sever management connection |
| Cluster config | permissions, certificates and roles, scheduled jobs | admin account, ACL, cert updates | R4: lockout/security |
| PVE 9.2 | dynamic load balancing state, maintenance disarm state, custom CPU config | enable/tune load balancing, custom CPU changes | R3/R4: compatibility and HA outage |

## Maintenance workflow
Start with a named plan: cluster + target nodes + expected outage + operator/time. Preflight: quorum and redundancy, backup freshness, HA manager state, guest placement, pending tasks, storage state, network reachability. Show a checklist and explicit user acknowledgment. Execute only a supported approved step; verify task postconditions. **No silent remediation or autonomous HA arm/disarm.**

## Network/firewall safety
A mobile app that modifies its own host's firewall can disconnect itself. For every write show rule diff, operator recovery path and out-of-band access requirement; when no recovery available, expose read-only view. A staged apply with server-side rollback must be **proven** before it is promised.

## Ceph health nuance
Status, pool usage, OSD availability and PG states can disagree; “HEALTH_OK” alone is not proof of redundancy. Units, error estimates and warnings must retain precise server semantics. Protect destructive pool and OSD workflows behind explicit reviewed runbooks.

## Change-control / audit
Locally record operation intent, profile/resource, timestamp, request mode, UPID and outcome without secrets. Proxmox server logs are the audit authority; VirtHelm cannot claim a tamperproof audit trail without an external append-only system. Optional export is redacted and user-initiated.

## Regression gates
A 3-node lab minimum for HA/quorum, controlled failure recovery scenarios, simulated loss of management link, Ceph sandbox with realistic warning states and 9.2-vs-8.4 capability gating. Any failure to recover from mutation must block the release.
