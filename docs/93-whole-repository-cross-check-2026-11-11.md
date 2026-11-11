# Whole-repository cross-check — 2026-11-11

> **Post-audit update:** the later [guarded snapshot lifecycle](94-implementation-guest-snapshot-lifecycle.md)
> slice implements stopped-only non-RAM rollback and snapshot deletion. The
> Recovery row and remaining-gap text below describe the audit-time baseline,
> not the current implementation. `PROJECT_STATUS.json` remains authoritative.

## Outcome and evidence boundary

Baseline: `fa41718a69e5083201f002ecc39c6e3e97420506` on `main` (restore planning, 0.1.45). This audit advances the application to **0.1.46** and fixes concrete safety, lifecycle, evidence-classification and status-documentation gaps. It is **not** a claim that every plan is implemented, that no defects can remain, or that production release gates are closed.

The review cross-checked the P0/P1 scope, premium epic/dependency plan, current status, implementation milestones through document 92, prior audits, controller/gateway/model/persistence paths, guest/provisioning/dialog flows, native hardening, tests and delivery workflows. Historical milestone documents remain historical; current-state contradictions are corrected in `PROJECT_STATUS.json`, the READMEs and guest UI.

## Plan-to-implementation cross-check

| Area | Implemented boundary reviewed | Remaining plan/release gap |
|---|---|---|
| F01/F02 connection/auth | HTTPS API tokens, staged verification, editable isolated profiles, secure vault, last-observed version, explicit origin-local TLS exception | physical Keystore/process-death/backup/TLS review; restricted-token matrix; ticket/MFA and managed private-CA enrollment |
| F03–F06 browsing | node/QEMU/LXC inventory, template separation, metrics/uptime/I/O, combined filters/sorts, favorites and saved views | real-device performance/accessibility at representative scale; fuller topology/capacity views |
| F07/F08 guest power | exact identity, live status, confirmation, synchronous reservation, one-shot submission | disposable-server mutation and fault-injection evidence on 9.2 and 8.4 |
| F09/F17 tasks | bounded recent history, conservative terminal results, local filters, on-demand bounded paged status/log inspection, TTL and post-terminal refresh | exhaustive task-worker/ACL/fault fixtures and richer log browsing |
| F10/F11 storage/preferences | partial-read reporting, no shared-capacity double counting, local appearance/refresh/accessibility preferences without credential writes | backend/device matrix and independent accessibility inspection |
| F12 offline/network | counts-only opt-in cache, transport classification, bounded GET retry, default-network recovery, foreground timers | full persistent guest/node detail cache remains missing; physical LAN/VPN/lifecycle validation |
| RRD and alerts | bounded explicit guest/node/storage history; foreground incident inbox, exact-target threshold rules, consecutive samples and hysteresis | acknowledgement/history, quiet hours/cooldown, background notifications/relay, capacity analytics |
| Config/permissions/templates | reviewed config allowlist, transient effective ACL hints, explicit template classification | config editing, broader capability/version gating, restricted ACL and backend fixtures |
| Provisioning | bounded full same-node clone, empty QEMU create and unprivileged LXC create, typed VMID confirmation, shared VMID reservation | richer disk/network/media/cloud-init/pool/HA/start provisioning; linked/cross-node/explicit-storage clone; mutation certification |
| Migration/deletion | bounded same-cluster migration; stopped non-template deletion with named confirmation and backup acknowledgement | local-resource/storage-remapped/force/bulk/cross-cluster variants; backup/quorum/HA safety proof and destructive lab tests |
| Recovery | read snapshots, create-only snapshots, one-off backup start, exact-guest archive visibility, evidence-limited confidence, GET-only alternate-VMID restore planning | rollback/delete snapshots, retention/scheduling/pruning, integrity/PBS verification, tested restore and all restore execution |
| Android/delivery | pinned Flutter, committed lock, generated hardened runner, native network observer, direct signed prerelease assets tied to checked SHA | physical phone/security/signing certification, dependency/license/SBOM review, repository-control enforcement and independent review |
| Wider premium catalogue | explicitly proposed backlog, not implemented-feature evidence | ticket/MFA/console, app lock/biometrics, native widgets/shortcuts/notifications, PBS/PDM, infrastructure/HA/Ceph/SDN/firewall management, payments and broader M5/M6 scope |

Progression into bounded M4 code does **not** establish completion of the earlier M0–M3 exit gates. The required dual-version mutation/device evidence is still missing. The premium catalogue remains `planned_unimplemented` by design; this audit does not bulk-promote its entries.

## Findings fixed

1. **Restore VMID availability was inferred from ACL-filtered inventory.** The controller now additionally calls the existing GET `/cluster/nextid?vmid=...` server assertion. Occupancy, denied access or failed verification blocks completion; 401 invalidates live write safety. Local pending/uncertain target reservations also block planning. No restore endpoint was added.
2. **Restore planning could outlive network/evidence changes.** Network-epoch and foreground checks discard obsolete controller results. Target nodes and freshly matching archives must be unique. The returned plan uses the freshly read archive metadata, not the earlier UI copy. A route-local revision prevents an in-flight plan from reappearing after archive refresh/storage change; backup submission invalidates previous planning evidence too.
3. **New guest-operation dialogs did not inherit power-dialog session redaction.** Snapshot, backup, migration, deletion, restore-plan and migration-target dialogs now observe the controller and redact on profile switch, same-profile reconnect or exact guest disappearance. Operation dialogs also show the connection and insecure-TLS context. The typed snapshot/migration/deletion inputs use route-owned form state instead of disposing external text controllers before the dialog route finishes closing.
4. **Recent mutation flows relied on cluster inventory state while later ACL/storage checks were pending.** Migration, snapshot creation, backup start and deletion now perform an exact-guest `/status/current` GET immediately before submission, then recheck session/freshness/foreground guards. A changed state or 401 issues no mutation. Deletion also rejects a changed live guest name so the typed destructive confirmation cannot silently apply to a renamed target. Server authorization and atomicity remain authoritative; these checks cannot eliminate cross-client races.
5. **Malformed/ambiguous identity could remain write-eligible.** Duplicate VMIDs across nodes or guest kinds now make inventory write-unsafe, reflecting the cluster-wide namespace. An explicitly malformed template marker is rejected instead of silently becoming a non-template workload. Valid neighboring rows remain displayable.
6. **Unknown backup-task state was classified as running.** Only explicit `running` now produces running evidence; unknown remains unknown. Archive/task evidence still cannot become integrity or tested-restore proof.
7. **Metadata-only profile edits rewrote unchanged encrypted credentials.** Edits with blank token fields now use a serialized metadata-only repository operation that invalidates old offline counts without writing the vault. Explicit token replacement retains the existing credential-update/rollback path.
8. **Current-state documentation lagged multiple merged milestones.** Status still described implemented LXC discovery/create, migration, deletion, snapshot create, backup start, archive discovery, confidence and restore planning as deferred in older feature entries. The guest Overview/Configuration tabs and README audit/recovery pointers were stale too. Current fields/text now distinguish implemented bounded workflows from genuinely deferred extensions.
9. **Malformed native preference types bypassed JSON-corruption recovery.** Several repository reads called the typed `getString` before their recovery block. A non-string stored value could therefore block profiles, onboarding or optional metadata before JSON handling ran. String reads now validate the underlying preference type, and deletion clears non-string favorites/views/rule roots as well. The existing corruption regression now covers native integer/boolean/list values and successful subsequent profile save/delete.

## Live read-only evidence

With the operator's explicit authorization, a **GET-only** smoke inspection was run against one **PVE 9.2.26** server. Normal certificate verification first rejected its untrusted certificate; the operator then explicitly approved a temporary exact-origin exception. No application profile, credential file, raw response fixture, real inventory, task log or signing material was committed or exported.

Two levels were exercised:

- Direct HTTPS response/schema checks: version, cluster resources, QEMU/LXC current status, snapshot lists, configurations, RRD, migration-precondition GETs, effective permissions, storage, recent tasks and exact-VMID backup content.
- **23 requests through the actual `DioPveGateway`**, behind an adapter that rejects any method except GET: version/inventory, storage/tasks, one task's status and bounded log parsing, QEMU/LXC status/snapshot/config/permission/RRD/archive parsers, node/storage RRD, next-free VMID, free-VMID assertion and occupied-VMID rejection. The occupied check returned HTTP 400 as expected. No VMID was reserved or guest/task mutation submitted.

The live inventory/storage/task/snapshot/permission parsers reported no malformed records in the sampled data; matching LXC archives parsed without ignored rows. The sampled stopped QEMU had no usable CPU/memory RRD points and correctly remained unavailable rather than inventing zero utilization. No names, VMIDs, private origin, configuration values, UPIDs, logs or credential values are included in this report.

This is **bounded read/parser smoke evidence**, not a complete integration suite. It does not validate PVE 8.4, separated/restricted token permissions, TLS server authenticity under the approved exception, mutation workers/outcomes, multi-node migration, all storage backends, end-to-end Android behavior, integrity or restoreability. `live_pve_tested` stays false for the required full release matrix; `live_pve_readonly_smoke_tested` records this narrower evidence.

Upstream contract reference: [Proxmox Cluster.pm](https://github.com/proxmox/pve-manager/blob/master/PVE/API2/Cluster.pm), `resources` (`VM.Audit` filtering) and `nextid` (unfiltered cluster-wide existence assertion). Existing reviewed endpoint contracts remain in [05-pve-api-contracts.md](05-pve-api-contracts.md).

## Automated validation and delivery evidence

- Pinned **Flutter 3.44.4 / Dart 3.12.2** in an isolated local SDK; committed `app/pubspec.lock` unchanged.
- Full `flutter analyze --fatal-infos`: clean.
- Full `flutter test --coverage --concurrency=2`: **347 passing runtime tests** from **290 declarations**, including parameterized cases; **41 new runtime regressions** in this audit.
- Formatting, documentation/premium/source checks, generated-runner hardening and **14 Python delivery tests** passed locally.
- Android runner regenerated with the pinned SDK; original ignored runner retained outside the repository. Debug compilation is performed with Java 17 and machine resource caps; its outcome is recorded in the completion note below rather than assumed from tests.
- Baseline exact-SHA main checks: [42913689940](https://github.com/s4daharu/VirtHelm/actions/runs/42913689940), successful; signed prerelease: [42914642302](https://github.com/s4daharu/VirtHelm/actions/runs/42914642302), successful. The audit commit requires its own fresh CI; baseline evidence is not relabeled as current-head evidence.

### Android build completion

The throttled local `flutter build apk --debug` succeeded with Flutter 3.44.4 and Java 17 (initial Gradle build: 532.9 seconds). After the preference-type recovery follow-up, the analyzer and all 347 tests passed again, and the incremental debug build succeeded in 37.3 seconds. Gradle daemons were stopped after both builds. No local release signing or production certification is claimed.

## Open gates and decisions

- Complete PVE 9.2 and 8.4 ACL/backend/mutation/fault-injection matrix; real destructive/restore tests need a separately authorized disposable environment. The supplied server was used read-only only.
- Physical Android Keystore/TLS/backup/process-death, LAN/VPN/default-network transitions, TalkBack/contrast/touch targets/200% text, and 200-guest/task performance validation.
- Full offline guest/node detail cache and the explicitly deferred functionality in the table above.
- Independent security/dependency/license/SBOM review, production signing/device verification and operational rollback/recovery evidence. No top-level license has been selected; this audit does not make that product/legal decision.
- Enforced branch-protection/ruleset and independent high-risk-change approval verification. Historical branch-control observations are not asserted as newly verified by this pass. Direct `main` delivery here is the operator's explicit request, not evidence that an independent review gate was met.
- Rotate the test token shared in the conversation. No credential rotation or other server write was attempted by this audit.

No finite source audit or passing synthetic suite can certify that nothing remains overlooked. The concrete defects above are corrected and regression-covered; remaining plan and environment-dependent gates are explicitly tracked rather than silently marked complete.
