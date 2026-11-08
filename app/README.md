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

The committed `pubspec.lock` is enforced. The bootstrap generates the Android runner, adds release Internet permission, disables cleartext and app backup, pins minSdk 26, and removes debug-key release signing. Release signing must be supplied outside Git.

## Implemented
- HTTPS-only named PVE profiles with strict endpoint validation and encrypted API-token storage.
- Certificate verification on by default, with an explicitly confirmed per-profile insecure opt-in for any host; saved profiles and active screens display warnings.
- Multiple isolated profiles with validated edit/switch/delete flows; edits preserve profile-local favorites/saved views and never forward credentials across redirects.
- Last successfully observed PVE server version is retained as non-secret profile metadata, refreshed on activation, and labelled as last-observed in the UI.
- Cluster nodes and QEMU/LXC inventory with search, freshness, CPU/memory/disk/uptime.
- Guest status/type/node filters, deterministic favorites/name/VMID/CPU/memory sorting, and up to 12 profile-scoped named saved views, without extra API requests.
- Read-only per-node storage and recent server task history with partial permission/error reporting, plus scoped on-demand task status and bounded log details for tracked/history tasks.
- Explicit on-demand 1h/24h/7d guest/node CPU-memory and per-storage used/total RRD history; metric samples stay transient and session-scoped.
- Foreground-only ALERT-001 incident inbox for explicit node-state problems, failed recent server tasks and failed/unknown session tasks; incomplete task reads retain prior failures instead of falsely resolving them.
- Profile-scoped ALERT-002/003 foreground CPU and storage threshold rules persisted as non-secret local metadata; missing/stale samples do not falsely resolve a prior firing.
- Transient GET failures use up to three total attempts with bounded jittered backoff; TLS/auth/redirect failures and all mutation POSTs are never automatically retried.
- Start/shutdown/reboot/force-stop confirmation with exact profile/node/type/VMID target.
- Fresh clean-inventory guard, live status preflight, exactly one POST, per-guest single-flight lock, no write auto-retry.
- UPID polling with terminal exit-status verification, bounded TTL, unknown-outcome lockout, and post-task reconciliation.
- Authentication revocation, stale/profile-switch/deletion races, malformed inventory and gateway contract regression tests.
- Device/light/dark/AMOLED theme preference, optional high-contrast and reduced-motion settings, optional foreground-only GET refresh (manual, 30/60/120 seconds), and node-metric display preference saved without credential-vault writes.
- Guest/node/storage RRD charts include visible percentage/time axes plus an on-demand timestamped sample table; chart alternatives remain read-only and transient.
- CI format/analyzer/coverage tests and Android debug APK compile verification.

## Not yet release-complete
No real PVE 8.4/9.2 lab matrix or production-signed APK is claimed. Physical-device certificate/backup/Keystore behavior, accessibility/font scaling, 200-guest performance, dependency/security review and signed-APK/device verification remain gates. Release signing secrets are configured; this alone does not verify a signed build. Full premium M2 scope such as cross-resource capacity analytics, alert duration/hysteresis/acknowledgement/history, Android notifications/background checks, persistent offline detail cache and richer topology/group views remains unimplemented. Bounded guest/node/storage charts, the foreground incident inbox, foreground CPU/storage thresholds, tag/pool filters, profile-scoped favorites and saved views are implemented at source level.

No ticket/MFA, console, snapshots/backups, migration/provisioning, PBS/PDM, host/HA/Ceph/SDN mutation, subscriptions or payments are included.

Use a dedicated least-privilege PVE API token and trusted HTTPS over LAN/VPN. API-token access does not provide console authentication. Disabling certificate verification permits server impersonation and token theft even on a LAN; it is not recommended for production. Edit a connection and save it with the switch off to restore certificate verification. See [TLS option](../docs/40-profile-tls-option.md). Native TLS regression tests generate disposable certificates using OpenSSL; install it before running `flutter test`.
