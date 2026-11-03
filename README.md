# VirtHelm — Flutter/Dart Android client for Proxmox VE

**Status:** implementation-ready documentation; **not yet a working app**.  
**Reviewed:** 2026-11-04. **Platform:** Android **phones only** (no iOS, web or desktop target).  
**Core backend:** user-operated Proxmox Virtual Environment (PVE); no proprietary cloud backend.

## What we are building
VirtHelm is an independent, unofficial Android mobile client to observe and administer Proxmox VE clusters via their officially exposed HTTPS REST API. Designed for operators who want a secure mobile-first cluster overview, node and guest details, permitted power operations, task progress, and later selected administrative functions.

**IMPORTANT:** no claim of 100% correctness can be made without live tests of each API method, PVE edition/version, permission configuration, and Android device. Documentation carefully marks verified statements, implementation choices, and unverified spikes. Never conflate Proxmox VE with Proxmox Backup Server or Proxmox Datacenter Manager.

## Reading order
| Phase | Documents |
|---|---|
| Product | [Product requirements](docs/01-product-requirements.md), [feature scope](docs/02-feature-scope.md), [UX](docs/03-ux-navigation.md) |
| Architecture | [Architecture](docs/04-architecture.md), [API contracts](docs/05-pve-api-contracts.md), [data models](docs/06-data-models.md) |
| Security | [Threat model, auth, transport](docs/07-security-auth.md), [console research/RFC](docs/08-console-rfc.md) |
| Delivery | [Error handling](docs/09-error-offline.md), [testing](docs/10-test-strategy.md), [backlog](docs/11-roadmap-backlog.md), [CI/release](docs/12-delivery-ci.md) |
| Assurance | [Risks and compatibility](docs/13-compatibility-risks.md), [research citations](docs/14-research-sources.md), [verification matrix](docs/15-verification-matrix.md), [ADRs](docs/16-decisions.md), [privacy](docs/17-privacy-legal.md), [developer setup](docs/18-setup-handbook.md) |

Also see [CSV endpoint index](docs/api-endpoint-index.csv), [manual API smoke-test recipes](examples/README.md), [security policy](SECURITY.md), [contributing](CONTRIBUTING.md), [definition of done](docs/19-definition-of-done.md).

## Premium expansion plan (v2 — planning only)

VirtHelm's **premium product vision** is specified in the 2026-11-04 extension. These are scoped **design and delivery plans**, not functioning features, builds, or validated live API integrations. Start with the [premium product strategy](docs/21-premium-product-strategy.md), [feature specification](docs/22-premium-feature-specification.md), and **200-feature [machine-readable catalogue](docs/premium-feature-catalog.csv)**.

| Topic | Planning documents |
|---|---|
| UX and Android polish | [Premium information architecture](docs/23-premium-ux-information-architecture.md), [Android native experience](docs/31-android-native-premium-experience.md) |
| QEMU/LXC operations | [Advanced guest workflows](docs/24-guest-lifecycle-advanced-workflows.md), [secure console and identity](docs/29-premium-security-identity-console.md) |
| Monitoring | [Alerting, capacity and insights](docs/25-monitoring-alerting-intelligence.md) |
| Disaster recovery | [Backup and PBS](docs/26-backup-disaster-recovery-pbs.md) |
| Cluster admin | [HA, Ceph, SDN, storage and networking](docs/27-cluster-ha-storage-ceph-sdn.md), [multi-site and PDM](docs/28-multisite-pdm-integration.md) |
| Engineering | [Flutter module contracts](docs/30-flutter-architecture-modules-and-contracts.md), [epic roadmap](docs/32-delivery-epics-sequencing.md), [release acceptance gates](docs/33-test-acceptance-release-gates.md) |
| Product and assurance | [Brand/pricing/privacy](docs/34-business-model-privacy-and-licensing.md), [verified-vs-proposed research](docs/35-research-verified-vs-proposed.md), [premium ADRs and risks](docs/36-premium-risks-and-design-decisions.md) |

**Compatibility scope:** PVE 9.2 primary / 8.4 regression; separately-gated PBS 4.2 and PDM 1.1. Background alerts from a sleeping Android phone are not guaranteed; an optional self-hosted relay is future research. All irreversible operations require explicit preflight and live integration evidence. For the extended documentation, run `python3 scripts/check_premium.py`.

## Architecture at a glance

```text
Android Flutter UI (phone-sized Material 3)
    -> ViewModels / state providers
       -> Domain use cases + repositories
          -> PVE HTTP service (typed models, permission/error layer)
          -> Keystore-backed secret storage
          -> Non-sensitive settings/cache
                 |
           TLS with validated certificate
                 |
      https://<pve-host>:8006/api2/json
                 |
             Proxmox VE cluster
```

## MVP scope (first usable release)
1. Multiple named cluster connection profiles, **API-token login first**, verified TLS, explicit connect/test, securely stored token, disconnect/delete.
2. Read-only dashboard: cluster resources, node list/status, VMs/containers with filtering, guest status/detail, storage overview, tasks list.
3. Allowed guest start/shutdown/stop/reboot with confirmation, role-aware errors, asynchronous task tracking, error recovery.
4. Android phone-only layout, accessible controls, manual refresh and foreground polling, offline cache clearly labeled as stale.
5. No embedded console in MVP: API token access is not sufficient for console endpoints. Investigate ticket/2FA and WebSocket security separately.

No virtualization-host-side agent, server deployment, persistent plaintext password, analytics SDK, public-facing port forwarding, or destructive operations without explicit confirmation.

## Bootstrap — after installing Flutter and Android Studio
The version-specific setup and security details are in [docs/18-setup-handbook.md](docs/18-setup-handbook.md).

```bash
flutter doctor -v
flutter create --platforms=android --project-name virthelm --org com.example app
cd app
flutter pub add dio flutter_riverpod go_router flutter_secure_storage shared_preferences
flutter pub add --dev flutter_lints mocktail
flutter analyze
flutter test
flutter run
```

The command makes an Android-only Flutter project in `app/` and intentionally does not create web/iOS/desktop runners. Review and pin dependency/Flutter versions before making a release. This archive contains the plans and checks, **not** a complete Flutter source implementation or a built APK.

## Private GitHub repository

The private project repository is [s4daharu/VirtHelm](https://github.com/s4daharu/VirtHelm) (private access required). Clone it with:

```bash
git clone https://github.com/s4daharu/VirtHelm.git
cd VirtHelm
python3 scripts/check_docs.py
```

Use normal pull requests for reviewed changes. Do not commit credentials or sanitized/live cluster data.
VirtHelm is independent software and is **not affiliated with, endorsed by, or officially distributed by Proxmox Server Solutions GmbH**.

## Key external references
- Official PVE docs source: https://github.com/proxmox/pve-docs
- Official PVE API viewer (live source of truth): https://pve.proxmox.com/pve-docs/api-viewer/
- Latest release listing checked 2026-11-04: https://proxmox.com/en/downloads/proxmox-virtual-environment
- Flutter guidance: https://docs.flutter.dev/app-architecture/guide
- Android network trust: https://developer.android.com/privacy-and-security/security-config

This project is **unofficial** and is not affiliated with Proxmox Server Solutions GmbH.
