# Premium Implementation Roadmap — Epics, Dependencies and Exit Criteria
This supersedes priority breadth in [11-roadmap-backlog.md](11-roadmap-backlog.md) while retaining secure MVP prerequisites. **No guaranteed dates** without team velocity, hardware and a live test lab.

## Milestone sequence
| Release train | Epic | Dependency | Ship gate |
|---|---|---|---|
| M0 Research/security baseline | verify PVE 8.4/9.2 contracts, TLS trust, versions, secure storage, architecture/CI | disposable PVE cluster, Android devices | all F0 critical unknowns resolved |
| M1 Foundations | Flutter shell, design tokens, profiles, API token, origin-bound HTTP, cache lifecycle | M0 | authenticated read fixtures and security tests |
| M2 Premium read cockpit | multi-profile dashboard, guests/nodes/storage/tasks, charts, search, favorites, notification center | M1 | no false status, accessibility and 200-guest performance |
| M3 Safe operator | power controls, task orchestration, RRD, backup status, snapshot read, alert foreground | M2 | 8.4 + 9.2 mutating-test evidence |
| M4 Premium operations | ticket/MFA, console if RFC passed, snapshot/backup execution, wizard-based creation/clone/migration | M3 | 2FA, console WebSocket, data-loss/retry tests |
| M5 Infrastructure pro | HA/Ceph/SDN/storage/firewall read -> targeted edits, maintenance planner, role views | M4 + multi-node lab | quorum, rollback/recovery runbooks reviewed |
| M6 Intelligence + ecosystem | local prediction, incident correlation, optional PBS/PDM/relay, native widgets | prior modules as appropriate | separate service compatibility and privacy gates |

Deliver feature flags continuously; use alpha/beta stages and promote individual epics only after evidence rather than waiting for every M6 idea.

## WBS with story IDs, sizes are placeholders
**EP-SEC (M0/M1):** SEC-01 TLS origin guard and certificate trust; SEC-02 Keystore and backup exclusions; SEC-03 token/cookie strategy; SEC-04 secrets redaction; SEC-05 app-lock/biometric; SEC-06 abuse/pen test.
**EP-CORE (M1/M2):** CORE-01 profile wizard; CORE-02 permission/capability discovery; CORE-03 session generation; CORE-04 caching/offline state (counts-only cache plus AND-011 separately opted-in 24-hour display-only stale node/guest identity list implemented; persistent detail/metrics/config/task caching remains gated); CORE-05 network retry/timeouts; CORE-06 observability.
**EP-UX (M1–M3):** UX-01 design kit; UX-02 dashboard; UX-03 explore/search; UX-04 guest details; UX-05 task timeline; UX-06 graphs; UX-07 accessibility/strings; UX-08 native system integrations.
**EP-GUEST (M3/M4):** GUEST-01 power/task lifecycle; GUEST-02 snapshots (bounded inventory/create/stopped-only non-RAM rollback/delete implemented; RAM-state/running rollback, descriptions, retention and snapshot trees remain gated); GUEST-03 backup action (bounded one-off start, exact-guest archive visibility, evidence-limited validation confidence, and GET-only same-node alternate-VMID restore planning/conflict preflight implemented; PBS-backed integrity verification and restore execution remain gated); GUEST-04 config read; GUEST-05 create/clone; GUEST-06 migration; GUEST-07 deletion safe flow; GUEST-08 console RFC.
**EP-INFRA (M5):** INF-01 node/cluster; INF-02 HA/dynamic load balancing; INF-03 Ceph; INF-04 SDN/firewall; INF-05 storage/ZFS; INF-06 maintenance planner; INF-07 audit/task correlation.
**EP-ALERT (M3/M6):** ALERT-01 foreground rules; ALERT-02 session-local acknowledgement, bounded earlier-signal timeline, mobile search/source filters, guarded batch review and bounded profile-scoped durable occurrence history implemented; catalog ALERT-007 foreground notification quiet hours/cooldown implemented with generic opt-in foreground-only Android delivery; ALERT-03/ALERT-009 first Android WorkManager node-state slice implemented with opt-in >=15-minute inexact checks, Keystore-encrypted worker credentials and coverage evidence; ALERT-010 device-wide secure-lock-screen privacy implemented with hidden-by-default or generic-only delivery; AND-010 generic notification deep link to the unlocked Incidents destination implemented without resource identifiers; shared per-profile native foreground/scheduled delivery deduplication implemented in 0.1.57; bounded opt-in background failed-task parity implemented in 0.1.58; scheduled threshold-rule parity, resource-specific notification links and authoritative correlation remain gated; ALERT-04 optional relay RFC; ALERT-05 insights and confidence.
**EP-ECO (M6):** ECO-01 PBS auth/adapter; ECO-02 PBS backup explorer; ECO-03 PDM auth/adapter; ECO-04 unified multi-site view; ECO-05 permissions/isolation verification.
**EP-REL (every train):** REL-01 toolchain pin/SBOM; REL-02 unit/contract/integration tests; REL-03 signed staging builds; REL-04 security review; REL-05 release note and rollback plan.

## Dependencies and critical path
SEC-01 -> CORE-01/05 -> CORE-02/03 -> UX-02/03/04 -> GUEST-01 -> REL staging. Ticket/MFA -> console; backup read -> backup execution -> restore; guest config read -> create/clone -> migrate; network/quorum observation -> HA/SDN changes; PDM/PBS adapter versions -> cross-site operations; relay auth/infrastructure -> remote push alerts.

## Delivery policies
- One story = feature + acceptance + contract evidence + security/ACL mapping + test fixture + UX states + documentation.
- “Progress” cannot be claimed by number of unverified API endpoints.
- PR approval mandatory for R2+ operations; independent reviewer for R3/R4 infrastructure/restore.
- Develop on feature branches; no direct production cluster testing of destructive or unproven workflows.
- Promotion must pass documented checklists in [33-test-acceptance-release-gates.md](33-test-acceptance-release-gates.md).

## Milestone definition of done
At each release: exact source versions, app commit and Android package identity pinned; CI passes; supported-version matrix tested; secrets/TLS no failures; UX/accessibility signoff; risk register updated; evidence stored without live secrets; release notes identify unsupported features honestly.
