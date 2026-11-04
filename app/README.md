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
- Read-only per-node storage and recent server task history with partial permission/error reporting.
- Start/shutdown/reboot/force-stop confirmation with exact profile/node/type/VMID target.
- Fresh clean-inventory guard, live status preflight, exactly one POST, per-guest single-flight lock, no write auto-retry.
- UPID polling with terminal exit-status verification, bounded TTL, unknown-outcome lockout, and post-task reconciliation.
- Authentication revocation, stale/profile-switch/deletion races, malformed inventory and gateway contract regression tests.
- CI format/analyzer/coverage tests and Android debug APK compile verification.

## Not yet release-complete
No real PVE 8.4/9.2 lab matrix or production-signed APK is claimed. Physical-device certificate/backup/Keystore behavior, accessibility/font scaling, 200-guest performance, dependency/security review and signed-APK/device verification remain gates. Release signing secrets are configured; this alone does not verify a signed build. Full premium M2 features such as charts, alerts/notification center, persistent offline cache and tag/group filters remain unimplemented. Profile-scoped favorites and basic status filters are already implemented.

No ticket/MFA, console, snapshots/backups, migration/provisioning, PBS/PDM, host/HA/Ceph/SDN mutation, subscriptions or payments are included.

Use a dedicated least-privilege PVE API token and trusted HTTPS over LAN/VPN. API-token access does not provide console authentication. Disabling certificate verification permits server impersonation and token theft even on a LAN; it is not recommended for production. Edit a connection and save it with the switch off to restore certificate verification. See [TLS option](../docs/40-profile-tls-option.md). Native TLS regression tests generate disposable certificates using OpenSSL; install it before running `flutter test`.
