# VirtHelm — Flutter/Dart Android client for Proxmox VE

**Status:** executable Android source with CI-verified debug builds; **not release-certified**.  
**Reviewed:** 2026-11-05. **Platform:** Android phones only.  
**Compatibility target:** PVE 9.2 primary / PVE 8.4 regression; live compatibility evidence remains required.

VirtHelm is an independent, unofficial mobile client for user-operated Proxmox VE. The repository contains a working Flutter implementation plus the product/security/release documentation. It has no mandatory vendor cloud backend.

## Implemented now

The current source implements HTTPS-only editable API-token profiles with retained last-observed PVE version metadata, Android secure credential storage, profile isolation, cluster/node/QEMU/LXC inventory, searchable guests with profile-scoped favorites, named saved views, status/type/node/tag/pool filters and selectable sorting, read-only storage overview, locally searchable/filterable recent server tasks with on-demand status and bounded log details, guest CPU/memory/disk/uptime, optional cumulative guest network/disk I/O totals, on-demand 1h/24h/7d average CPU/memory RRD history, and guarded QEMU/LXC start/shutdown/reboot/force-stop actions with live preflight and UPID tracking. Local F11 settings now persist device/light/dark appearance, optional foreground-only timed read refresh (manual by default), and whether optional node metrics appear on Home.

Write safety includes exact profile/node/type/VMID identity, fresh clean inventory, single-flight submission, no automatic mutation retry, ambiguous-outcome lockout, bounded task verification, and authoritative refresh after terminal tasks. Transient read-only GET failures use bounded jittered retries; mutation POSTs are never replayed. Redirects and cleartext are blocked. Certificate validation is enabled by default; an explicitly confirmed, saved per-connection insecure option is available for any HTTPS host. It allows server impersonation and token theft, even on a LAN. TLS exceptions remain labeled in the header, connection picker and Settings rather than a persistent banner; guest action confirmations also warn. Android default-network loss pauses polling and disables writes until a fresh authenticated read. See [TLS option](docs/40-profile-tls-option.md).

This is still **not** a production release. Real PVE 8.4/9.2 fixtures, ACL matrices, physical-device TLS/backup/accessibility/performance tests, release signing, and independent security review remain open. See the [tag and pool browsing implementation](docs/60-implementation-tag-pool-browsing.md), the [guest RRD history implementation](docs/59-implementation-guest-rrd-history.md), the [2026-11-05 pre-merge whole-repository audit](docs/58-premerge-whole-repository-audit-2026-11-05.md), [guest I/O counters and session-isolation fix](docs/57-implementation-guest-io-counters.md), and the [F09 task-history filtering increment](docs/56-implementation-f09-task-history-filters.md) and the [F09 task log paging and refresh increment](docs/55-implementation-f09-task-log-pages.md), and the [F12 Android connectivity increment](docs/54-implementation-p0-android-connectivity.md), [F12 offline overview cache](docs/53-implementation-p0-offline-overview.md), [F12 transport-error classification](docs/52-implementation-p0-transport-errors.md), [F09 task detail implementation](docs/51-implementation-p0-task-details.md), [F11 settings implementation](docs/50-implementation-p0-local-preferences.md), [current whole-repository audit](docs/49-whole-repository-audit-2026-11-04.md), [GET retry implementation note](docs/48-implementation-p0-read-retries.md), [server-version implementation note](docs/47-implementation-p0-server-version.md), [profile-editing implementation note](docs/46-implementation-p0-profile-editing.md), and [Definition of Done](docs/19-definition-of-done.md).

## Build and test

Use the pinned Flutter **3.44.4** baseline (also recorded in `app/.flutter-version`) and an Android SDK:

```bash
flutter doctor -v
bash scripts/bootstrap_android.sh
cd app
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test --coverage
flutter build apk --debug
```

`scripts/bootstrap_android.sh` generates only the Android runner, applies manifest/Gradle hardening, restores the committed dependency lockfile, and resolves with `--enforce-lockfile`. Release signing is intentionally not stored in Git.

## APK downloads without Actions artifact storage

After **Docs and Android checks** succeeds for a push to `main`, **Android split APK prerelease** runs automatically for that exact checked commit. It can also be started manually from Actions on `main`. The signed ARM64/ARMv7 APKs and `SHA256SUMS.txt` are uploaded directly from the build runner to [GitHub Releases](https://github.com/s4daharu/VirtHelm/releases), following NovelBridge's release-asset approach. The run summary includes release and direct download links; release assets are publicly downloadable from the GitHub Releases page.

Neither workflow uploads Actions artifacts. Normal push/PR checks still compile a debug APK but do not retain it. Previously uploaded artifacts are not deleted by this change and remain until expiration or manual removal; build caches are separate and unchanged. Release publication is automatic only after successful main-branch CI (or manual dispatch on `main`) and does not imply production certification.

## Current scope vs roadmap

The implemented M1/M2 slices do **not** equal the whole premium roadmap. Guest CPU/memory RRD history now has a bounded on-demand slice; broader node/storage charts, notification center/alerts, full offline guest/detail cache, richer topology/group views, biometric app lock, ticket/MFA, console, snapshots/backups, PBS/PDM, migrations/provisioning, infrastructure mutation, and signed distribution remain future/gated work.

The premium planning catalogue remains available as [docs/premium-feature-catalog.csv](docs/premium-feature-catalog.csv). It is a proposal/verification backlog, not the current implementation tracker; use `PROJECT_STATUS.json` and the [current whole-repository audit](docs/49-whole-repository-audit-2026-11-04.md) for implemented scope and remaining gaps.

Read the product baseline in [docs/01-product-requirements.md](docs/01-product-requirements.md), API contract inventory in [docs/05-pve-api-contracts.md](docs/05-pve-api-contracts.md), security model in [docs/07-security-auth.md](docs/07-security-auth.md), test strategy in [docs/10-test-strategy.md](docs/10-test-strategy.md), premium roadmap in [docs/32-delivery-epics-sequencing.md](docs/32-delivery-epics-sequencing.md), and release gates in [docs/33-test-acceptance-release-gates.md](docs/33-test-acceptance-release-gates.md).

## Repository and security

The public repository is `s4daharu/VirtHelm`. Never commit PVE credentials, private CA keys, signing keys, real inventories, or task logs.

No open-source license has been selected yet. Public source visibility does not itself grant permission to reuse, modify, or redistribute the code; add a top-level `LICENSE` when the licensing decision is made. Use a least-privilege PVE API token and a trusted HTTPS certificate over LAN/VPN; do not expose PVE port 8006 publicly as a default access pattern.

VirtHelm is independent software and is **not affiliated with, endorsed by, or officially distributed by Proxmox Server Solutions GmbH**.
