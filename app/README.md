# VirtHelm Android app — audited M1/M2 preview

This folder contains executable Flutter/Dart source for Android phones only. It is an implementation preview, not the complete premium roadmap or a production-certified release.

## Setup
Use Flutter **3.44.4** and run from the repository root:

```bash
bash scripts/bootstrap_android.sh
cd app
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test --coverage
flutter build apk --debug
```

The committed `pubspec.lock` is enforced. The bootstrap generates the Android runner, adds network and notification permissions, disables cleartext and app backup, pins minSdk 26, installs the reviewed adaptive launcher icon resources plus the WorkManager scheduled-check worker, and removes debug-key release signing. Release signing must be supplied outside Git.

## Implemented
- HTTPS-only named PVE profiles with strict endpoint validation and encrypted API-token storage.
- Certificate verification on by default, with an explicitly confirmed per-profile insecure opt-in for any host; saved profiles and active screens display warnings.
- Multiple isolated profiles with validated edit/switch/delete flows; edits preserve profile-local favorites/saved views and never forward credentials across redirects.
- Last successfully observed PVE server version is retained as non-secret profile metadata, refreshed on activation, and labelled as last-observed in the UI.
- Cluster nodes and QEMU/LXC inventory with search, freshness, CPU/memory/disk/uptime.
- QEMU/LXC templates are classified from the existing live cluster inventory, exposed through an explicit Templates filter and saved views, never authorize power actions, and can enter the guarded full same-node clone wizard.
- Guests exposes a guarded empty-QEMU create wizard: online node, VMID, conservative name, cores, memory and onboot only; it creates a stopped VM shell with no disk, network, media, pool, HA, restore or automatic start fields.
- Guests also exposes a guarded unprivileged LXC create wizard from live-discovered existing `vztmpl` content and active `rootdir` storage, with typed VMID confirmation, storage ACL hints and one-shot `vzcreate` task tracking. Privileged/custom-rootfs/networked/richer container provisioning remains gated.
- Guarded same-cluster QEMU/LXC migration and stopped non-template deletion, with explicit typed confirmation, fresh status/identity/ACL preflight, one-shot submission, uncertain-outcome locking and post-task reconciliation.
- Guest status/type/node/template filters, deterministic favorites/name/VMID/CPU/memory sorting, and up to 12 profile-scoped named saved views, without extra API requests.
- Read-only per-node storage and recent server task history with partial permission/error reporting, plus scoped on-demand task status and bounded log details for tracked/history tasks.
- Explicit on-demand 1h/24h/7d guest/node CPU-memory and per-storage used/total RRD history; metric samples stay transient and session-scoped.
- On-demand read-only QEMU/LXC snapshot inventory, exact-profile/session/guest scoped and never persisted; guarded creation, stopped-only non-RAM rollback and snapshot deletion are available through mobile action sheets and typed-name confirmations. RAM-state/running rollback and snapshot descriptions/trees remain gated.
- Guarded one-off QEMU/LXC `vzdump` backup submission plus on-demand exact-guest backup archive visibility from active backup-capable storage. An evidence-limited confidence card classifies archive/task evidence as not assessed, insufficient, or partial; it never claims integrity verification or restoreability. Visible archives can enter a GET-only same-node alternate-VMID restore plan/conflict preflight that rechecks archive visibility, target storage, VMID availability and ACL hints without submitting a restore.
- On-demand QEMU/LXC configuration inspection using an explicit reviewed allowlist; passwords, SSH keys, arbitrary args/hooks/descriptions and unknown future keys are never copied into the display model.
- On-demand exact-guest effective permission hints from `/access/permissions`, kept transient and presentation-only; they never replace Proxmox ACL enforcement or VirtHelm's live mutation preflight.
- Foreground-only ALERT-001 incident inbox for explicit node-state problems, failed recent server tasks and failed/unknown session tasks; incomplete task reads retain prior failures instead of falsely resolving them. ALERT-02 adds local acknowledgement, needs-review/acknowledged/earlier mobile triage plus bounded profile-scoped durable occurrence history that excludes task UPIDs/logs; it never marks infrastructure healthy.
- Profile-scoped ALERT-002/003 foreground CPU and storage threshold rules persisted as non-secret local metadata; missing/stale samples do not falsely resolve a prior firing.
- ALERT-006 adds 1–10 consecutive usable foreground samples before firing and 0–20 percentage points of clear hysteresis, with backward-compatible saved-rule defaults.
- ALERT-007 adds opt-in generic foreground Android incident notifications with profile-scoped quiet hours and cooldown. Suppression affects notification delivery only; in-app health/history stay authoritative.
- ALERT-009 adds an opt-in Android WorkManager node-state check for certificate-verified profiles. It uses an inexact >=15-minute cadence, connected-network constraint, GET-only PVE read, Android-Keystore-encrypted worker token copy, generic notifications and explicit last-attempt/last-complete coverage evidence. It is not 24/7 monitoring or critical paging.
- VirtHelm 0.1.58 adds a separately opted-in bounded recent failed-task scan to scheduled checks: at most 20 task rows on up to 16 visible nodes, GET-only, with conservative incomplete-read handling and only generic per-profile category state retained natively.
- ALERT-010 adds one device-wide lock-screen privacy setting shared by foreground and scheduled incident notifications: hide entirely on a secure lock screen by default, or allow only the generic VirtHelm alert. No public/sensitive lock-screen mode is exposed.
- AND-010 makes both incident notification paths open the unlocked in-app Incidents destination through one immutable explicit Android intent. The intent carries no profile/resource selector, VMID, task ID or other infrastructure identifier.
- VirtHelm 0.1.57 shares one private native per-profile last-delivery ledger between foreground and scheduled notification paths. Each path applies its own configured cooldown against the last successful delivery from either mode; only a SHA-256-derived profile key and timestamp are stored.
- AND-011 adds a separate per-profile opt-in for a 24-hour bounded stale inventory list: node name/status plus guest name, VMID, type, node, status and template marker only. Cached cards are visibly not-live and non-interactive; metrics/config/storage/task data, credentials and raw responses are not persisted.
- Transient GET failures use up to three total attempts with bounded jittered backoff; TLS/auth/redirect failures and all mutation POSTs are never automatically retried.
- Start/shutdown/reboot/force-stop confirmation with exact profile/node/type/VMID target.
- Fresh clean-inventory guard, live status/identity preflight, exactly one POST, per-guest/template single-flight lock, no write auto-retry.
- Full same-node template clone with suggested/collision-checked destination VMID, typed VMID confirmation, source VM.Clone and destination VM.Allocate hints, full=1, default Proxmox storage placement, and UPID reconciliation. Datastore/SDN authorization remains server-authoritative.
- UPID polling with terminal exit-status verification, bounded TTL, unknown-outcome lockout, and post-task reconciliation.
- Authentication revocation, stale/profile-switch/deletion races, malformed inventory and gateway contract regression tests.
- Device/light/dark/AMOLED theme preference, optional high-contrast and reduced-motion settings, optional foreground-only GET refresh (manual, 30/60/120 seconds), and node-metric display preference saved without credential-vault writes.
- Guest/node/storage RRD charts include visible percentage/time axes plus an on-demand timestamped sample table; chart alternatives remain read-only and transient.
- CI format/analyzer/coverage tests and Android debug APK compile verification.

## Not yet release-complete
The [2026-11-11 cross-check](../docs/93-whole-repository-cross-check-2026-11-11.md) records bounded GET-only HTTP and actual-gateway/parser smoke evidence from one PVE 9.2.26 server, plus the safety fixes and plan gaps present before the later [snapshot lifecycle slice](../docs/94-implementation-guest-snapshot-lifecycle.md). It is not mutation, PVE 8.4, restricted-ACL or physical-device certification.

No real PVE 8.4/9.2 lab matrix or production-certified APK is claimed. Physical-device certificate/backup/Keystore behavior, accessibility/font scaling, 200-guest performance, dependency/security review and production device/signing verification remain gates. CI has published signed prerelease APKs, but prerelease signing is not production certification. Full premium M2 scope such as cross-resource capacity analytics, authoritative incident correlation, scheduled threshold-rule parity, resource-specific notification links, persistent offline guest/node detail/metrics/config/task cache and richer topology/group views remains unimplemented. Bounded guest/node/storage charts, the foreground incident inbox, foreground CPU/storage thresholds, tag/pool filters, profile-scoped favorites and saved views are implemented at source level.

No ticket/MFA, console, configuration editing, RAM-state/running snapshot rollback, snapshot descriptions/retention/trees, backup scheduling/retention/PBS-backed archive integrity verification/restore execution, overwrite/cross-node restore and richer restore mapping, privileged/custom-rootfs/networked/richer LXC provisioning, QEMU disk/storage/network/media/cloud-init/pool/HA/start provisioning, linked/cross-node or explicit-storage clone variants, advanced migration variants, PBS/PDM, host/HA/Ceph/SDN mutation, subscriptions or payments are included.

Use a dedicated least-privilege PVE API token and trusted HTTPS over LAN/VPN. API-token access does not provide console authentication. Disabling certificate verification permits server impersonation and token theft even on a LAN; it is not recommended for production. Edit a connection and save it with the switch off to restore certificate verification. See [TLS option](../docs/40-profile-tls-option.md). Native TLS regression tests generate disposable certificates using OpenSSL; install it before running `flutter test`.
