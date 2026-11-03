# Premium Research Update — Evidence and Open Questions
**Research date:** 2026-11-04. This is a research **register**, not a declaration of fully correct API schema or finished functionality. Official documents substantiate upstream product capabilities; VirtHelm feature behaviors remain proposed until tested.

## Officially documented upstream facts
| Ref | Official source | Substantiated | Implications |
|---|---|---|---|
| PX-01 | https://proxmox.com/en/about/company-details/press-releases/proxmox-virtual-environment-9-2 | PVE 9.2 released 2026-05-21; dynamic load balancer, WireGuard/BGP SDN, custom CPU model UI, HA arm/disarm | design F2 compatibility gates, do not assume available on 8.4 |
| PX-02 | https://www.proxmox.com/en/downloads/proxmox-virtual-environment/documentation | official PVE 9.2 and 8.4 admin guides listed | keep regression matrix for both |
| PX-03 | https://github.com/proxmox/pve-docs/blob/master/pveum.adoc | PVE API tokens, separated privileges and VM/system console limitations | token vs ticket auth modules |
| PX-04 | https://github.com/proxmox/pve-docs/blob/master/pveproxy.adoc | pveproxy HTTPS API port 8006 | direct HTTPS default |
| PX-05 | https://pve.proxmox.com/pve-docs/api-viewer/ | canonical endpoint/ACL documentation | endpoint-by-endpoint verification still pending (automated page returned 403) |
| PX-06 | https://proxmox.com/en/about/company-details/press-releases/proxmox-backup-server-4-2 | PBS 4.2 released 2026-04-29; namespace moves, sync encryption, S3-backend metrics | separate PBS adapter/fixture |
| PX-07 | https://pbs.proxmox.com/docs/api-viewer/index.html | PBS has its own official API viewer | do not transplant PVE endpoints |
| PX-08 | https://proxmox.com/en/about/company-details/press-releases/proxmox-datacenter-manager-1-1 | PDM 1.1 released 2026-05-28, cross-remote guest/snapshot view, Ceph, provisioning | separate PDM adapter/ACL |
| PX-09 | https://pdm.proxmox.com/docs/ | PDM 1.1.9 docs dated 2026-10-14 | check versioned PDM schema |
| AD-01 | https://developer.android.com/develop/background-work/background-tasks/persistent/getting-started/define-work | periodic WorkManager repeat >=15 min, execution may be deferred | no false always-on alerts |
| AD-02 | https://developer.android.com/develop/ui/compose/notifications/notification-permission | Android 13+ notification permission | explicit permission UX |
| AD-03 | https://developer.android.com/develop/ui/views/layout/edge-to-edge | Android 15 target SDK 35+ edge-to-edge | safe insets on phones |
| FL-01 | https://docs.flutter.dev/app-architecture/guide | views/viewmodels, repositories and services recommended | Flutter MVVM boundaries |
| SE-01 | https://cheatsheetseries.owasp.org/cheatsheets/Mobile_Application_Security_Cheat_Sheet.html | credential/network/storage security practices | mandatory release threat model |

## Technical unknowns requiring verification
- Exact PVE 9.2 and 8.4 API calls, role/path ACLs, JSON schemas and status edge cases for each [feature ID](premium-feature-catalog.csv).
- Device-safe interactive VNC/WebSocket ticket handshake under PAM/PVE/LDAP/OIDC and second-factor variations.
- PVE backup/snapshot retention and restore feasibility on all storage backends; PBS and PDM auth handshake details.
- Ceph/HA/SDN operations that change quorum, routing, resilience or irreversible data states.
- Accurate metric fields, units, RRD intervals and high-concurrency API costs.
- Self-hosted relay event architecture, delivery SLA, privacy footprint and public network protection.
- Android runtime compatibility for selected packages; pin after Flutter build, toolchain and license audit.
- Name and commercial product clearance.

## How to promote from PLAN to VERIFIED
For each endpoint: record canonical API viewer URL/source revision, PVE version and patch, method/path and schema/privileges, input and expected output, separate read and mutation ACL trials, success/failure sanitized fixture SHA256, build/app commit, Android device + auth mode, PASS/FAIL with reviewer. Product/marketing claim only after end-to-end tests. Do not replace pending evidence with guesswork.

## Scope-of-research limitations
Review used Proxmox official release/documentation pages, Flutter/Android/OWASP official sources and existing repository API register. **No PVE lab was connected in this research turn.** The official live PVE API viewer returned HTTP 403 to automated retrieval; therefore this plan deliberately does not fabricate endpoint-level verification. Other dynamic docs can be incomplete without JS.
