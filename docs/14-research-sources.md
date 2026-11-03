# Research Register and Source Provenance

**Research review date:** 2026-11-04. Primary authorities preferred. Some websites expose the documentation only via JS/API viewer or reject automated fetching; this is an explicit limitation of verification, not a license to invent response schemas. Source links may change; freeze a versioned snapshot when development starts.

| ID | Authority | URL | Supported facts | Confidence |
|---|---|---|---|---|
| S01 | Proxmox official download page | https://proxmox.com/en/downloads/proxmox-virtual-environment | PVE 9.2 latest ISO listed, PVE 8.4 also available | Official page observed 2026-11-04 |
| S02 | Proxmox 9.2 release | https://proxmox.com/en/about/company-details/press-releases/proxmox-virtual-environment-9-2 | PVE 9.2 released 2026-05-21 | Official press release |
| S03 | Proxmox official PVE user management documentation mirror | https://github.com/proxmox/pve-docs/blob/master/pveum.adoc | API token header, privilege separation, expiry, console limitations | Official source code documentation |
| S04 | Proxmox official pveproxy documentation mirror | https://github.com/proxmox/pve-docs/blob/master/pveproxy.adoc | PVE API via HTTPS port 8006, node forwarding | Official source code documentation |
| S05 | Proxmox official PVE GUI docs mirror | https://github.com/proxmox/pve-docs/blob/master/pve-gui.adoc | noVNC/SPICE/xterm.js exist in GUI; mobile browser available | Official source code documentation |
| S06 | Proxmox VE API viewer | https://pve.proxmox.com/pve-docs/api-viewer/ | Endpoint methods, parameters, output types and privileges | **Canonical; viewer content not exhaustively harvested for this edition** |
| S07 | Proxmox pve-manager implementation mirror | https://github.com/proxmox/pve-manager | Nodes/cluster/services API implementation source | Official code; endpoint-level verification still pending |
| S08 | Proxmox QEMU implementation mirror | https://github.com/proxmox/qemu-server | VM lifecycle implementation | Official code; versioned endpoint verification pending |
| S09 | Proxmox LXC implementation mirror | https://github.com/proxmox/pve-container | LXC lifecycle implementation | Official code; versioned endpoint verification pending |
| S10 | Flutter official architecture guide | https://docs.flutter.dev/app-architecture/guide | Views/viewmodels, repositories and services | Official recommendation |
| S11 | Flutter official architecture recommendations | https://docs.flutter.dev/app-architecture/recommendations | separation of concerns and router guidance | Official recommendation |
| S12 | Flutter Android setup | https://docs.flutter.dev/platform-integration/android/setup | Android SDK tooling, device setup | Official instructions |
| S13 | Android network security config | https://developer.android.com/privacy-and-security/security-config | trusted CAs, cleartext disable, debug-only trust | Official Android docs |
| S14 | Android certificate/pinning cautions | https://developer.android.com/privacy-and-security/security-ssl | pinning change/rotation risk | Official Android docs |
| S15 | flutter_secure_storage package | https://pub.dev/packages/flutter_secure_storage | Android Keystore implementation and backup considerations | Package publisher docs; validate installed release |
| S16 | flutter_secure_storage changelog | https://pub.dev/packages/flutter_secure_storage/changelog | v11 changes Android minSdk to 24/compileSdk to 37, migration impacts | Package publisher docs observed 2026-11-04 |
| S17 | GitHub CLI repository creation | https://cli.github.com/manual/gh_repo_create | manual private repository creation workflow | Official GitHub CLI docs |

## What was deliberately **not** certified
- Current Proxmox live installation endpoint permissions or precise response schema for each PVE 8.4 and 9.2 build.
- Successful Android builds (Flutter SDK is not present in this authoring environment).
- noVNC functionality with API token (official docs say it cannot access console endpoints).
- Full ticket/TFA handshake compatibility with all authentication realms.
- Release-ready compliance with a future Google Play SDK deadline; check current policy when publishing.
- Ownership of app name, icon, or third-party plugin license obligations.

## How to close evidence gaps
An engineer must open each supported PVE version's local API viewer, save a copy of endpoint schema (method, input, permission, response), create sanitized fixtures from a disposable lab, run all success and failure paths and attach CI/device result hashes. Mark each unverified row in `15-verification-matrix.md` with evidence; never change it to “verified” based only on an AI-generated example.
