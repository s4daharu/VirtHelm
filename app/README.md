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
- Multiple isolated profiles, explicit switch/delete, no redirect credential forwarding.
- Cluster nodes and QEMU/LXC inventory with search, freshness, CPU/memory/disk/uptime.
- Read-only per-node storage and recent server task history with partial permission/error reporting.
- Start/shutdown/reboot/force-stop confirmation with exact profile/node/type/VMID target.
- Fresh clean-inventory guard, live status preflight, exactly one POST, per-guest single-flight lock, no write auto-retry.
- UPID polling with terminal exit-status verification, bounded TTL, unknown-outcome lockout, and post-task reconciliation.
- Authentication revocation, stale/profile-switch/deletion races, malformed inventory and gateway contract regression tests.
- CI format/analyzer/coverage tests and Android debug APK compile verification.

## Not yet release-complete
No real PVE 8.4/9.2 lab matrix or production-signed APK is claimed. Physical-device certificate/backup/Keystore behavior, accessibility/font scaling, 200-guest performance, dependency/security review and release signing remain gates. Full premium M2 features such as charts, favorites, alerts/notification center, persistent offline cache and richer saved filters remain unimplemented.

No ticket/MFA, console, snapshots/backups, migration/provisioning, PBS/PDM, host/HA/Ceph/SDN mutation, subscriptions or payments are included.

Use a dedicated least-privilege PVE API token and trusted HTTPS over LAN/VPN. API-token access does not provide console authentication. There is no certificate bypass.
