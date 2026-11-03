# Multi-Site, Multiple Profiles and Proxmox Datacenter Manager (PDM)
Multi-profile is core and **direct PVE** remains default. Native PDM support is an optional separately authenticated future adapter, not a thin wrapper around PVE calls.

## Supported connection concepts
1. **PVE profile:** endpoint + verified TLS trust + least-privilege PVE token or user ticket, cluster UUID/name evidence, local alias.
2. **PBS profile:** separately validated API and datastore scope; may be referenced by PVE storage but its credentials are never inherited.
3. **PDM profile:** native PDM API/permissions only after compatibility evidence; PDM 1.1 released 2026-05-28 with centralized remote health, guest operations, snapshots and Ceph dashboards.
4. **Optional relay registration:** independent self-hosted endpoint with per-device revocable keys; no inherited PVE root token.

## Multi-site UX
Profiles grouped by customer/location/purpose; color accents are secondary to explicit names. A universal read-only dashboard may aggregate non-sensitive summaries when allowed. Any mutation must leave cross-site view and display one exact profile, node and resource with fresh data. No global bulk delete, mass node restart or cross-tenant copy-paste.

## Data isolation invariant
Every request, cached record, task and notification is keyed by (profileId, origin, backendKind, sessionGeneration). Switching profiles invalidates old providers, cancels in-flight futures and discards old UI actions. Same VMID in two sites is **never** the same entity. Secret lookup uses opaque credential handle; do not serialize secrets into general profile models. No token forwarding across origin/reverse proxy redirects.

## PDM 1.1 feature candidates
- cross-remote read-only site and guest inventory, centralized tasks, Ceph overview;
- read-only snapshot views and resource status;
- PDM-provided guest actions only with its **own** permissions, precise endpoint version and server state;
- site topology and personalized site views;
- avoid duplicating PDM account/subscription/automatic-install provisioning before full research and safety review.

## Secure onboarding
Manual HTTPS URL + verified certificate; optional QR onboarding only if code is produced by a **trusted on-site process** and contains no long-lived plain token by default. Reject untrusted QR redirect URLs and local LAN discovery that silently connects. Permissions and trust summary must be intelligible before save.

## Device migration
Optional export of aliases, layouts, filters, favorited IDs and rules **without secrets**. Encrypted credential transfer requires a separate design with user-managed key and reversible test; never let Android device backups silently sync private API secrets. Allow profile delete that purges associated cache and registrations.

## PDM test plan
Compare remote inventory with direct PVE source, test unavailable site, stale PDM replication, partial permissions and revoked token. Prove PDM and PVE identities cannot collide and that actions route to the correct backend. PDM version independence: supporting PVE 9.2 does not guarantee PDM 1.1 compatibility.

## Sources
- PDM official docs: https://pdm.proxmox.com/docs/
- PDM 1.1 announcement: https://proxmox.com/en/about/company-details/press-releases/proxmox-datacenter-manager-1-1
