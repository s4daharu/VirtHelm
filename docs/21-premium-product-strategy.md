# VirtHelm Premium Product Strategy — v2
Reviewed 2026-11-04. **Plans only: no app code, verified API interaction, or released premium feature is implied.**

## Product definition
VirtHelm is an independent **Android phone-only** Flutter/Dart control cockpit for Proxmox VE. It makes infrastructure observable, recoverable, and deliberately manageable with excellent one-hand ergonomics. Product goal: the best trustworthy **mobile-first operator experience**, not feature parity by forcing desktop forms onto a phone. PVE remains the source of truth; ACLs and operational correctness trump UI convenience.

## Personas and jobs
| Persona | Primary job | Must not assume |
|---|---|---|
| Homelab owner | Quickly see failures, start a guest, recover from a stopped VM, securely access console | Has public network access or a dedicated alert server |
| Operator | Triage incidents, review task logs, live guest state, run approved operations | Has cluster-admin ACL |
| MSP operator | Switch between many customer-owned sites without crossing secrets or data | Cross-customer single sign-on or hosted service |
| Infrastructure engineer | Diagnose Ceph/HA/SDN and evaluate safe maintenance steps | UI is a substitute for change-control |
| Disaster-recovery operator | Find last usable backup, assess restore plan, follow tracked procedure | Backup presence proves restore success |

## Premium experience principles
1. **Status before action:** always show cluster identity, origin, state freshness and current privilege scope.
2. **Explain confidence:** distinguish confirmed read, inferred health, unknown, stale, and permission-restricted.
3. **Fast when safe:** favorites, search, widgets, action menus and reusable filters; never one-tap destructive workflows.
4. **Invisible network waste:** deduplicate, throttle, backoff, poll only foreground unless the user explicitly enables constrained background checks.
5. **Private by default:** direct local/VPN connections; no mandatory VirtHelm account, cloud telemetry, or credential upload.
6. **Recoverable operations:** preview preconditions, verify side effects, display authoritative UPID and task exit; surface unknown state honestly.
7. **Distinctive UX:** beautifully finished dark/light Material 3, crisp timelines/graphs, low-jank long lists, accessibility and understandable errors.

## Release lanes (not paid entitlement tiers)
- **Foundation F0:** secure profiles, discovery, read-only inventory, VM/LXC power and task tracking, polished Android basics.
- **Operator F1:** richer graphs, log explorer, snapshots, backup execution, guest configuration read, secure interactive console after auth RFC.
- **Pro F2:** guided provisioning/cloning/migrations; HA, Ceph, SDN, firewall, storage, maintenance and reusable runbooks; guarded high-risk edits.
- **Intelligence F3:** local capacity forecasts, incident correlation, recommendation explainers, optional opt-in on-device analysis.
- **Ecosystem F4:** optional separately authenticated PBS 4.2 and PDM 1.1 integrations; enterprise multi-site and optional self-hosted relay.

These lanes control engineering order; they do **not** automatically mean subscriptions or paywalls.

## Product success measures (proposed validation targets)
- Under 30 seconds to identify selected cluster and latest failing workload on a cached profile (test with real operators).
- A guest action always has **exactly one** clear final state: rejected, completed, failed, or unknown/investigate; never “success” solely on HTTP 200.
- Median cached dashboard usable within 1.5s on benchmark device, network-dependent live loads separately measured.
- UI target 60fps on 200-guest fixtures, <1% pre-release crash rate on managed tests; these are **targets**, not achieved results.
- Every shipped high-risk operation has preflight, postconditions, failure-state guidance and a recovery link.
- Zero known plaintext token exposures or TLS bypasses at release.

## Scope boundaries
Do not invent unsupported PVE APIs, auto-execute maintenance, SSH to nodes by default, create a backend solely for marketing telemetry, claim continuous push alerts from a sleeping phone, or store encrypted backup keys in app analytics. No iOS/web/desktop client. Android phone is the only consumer interface; optional future self-hosted relay would be an infrastructure component, not a second user app.
