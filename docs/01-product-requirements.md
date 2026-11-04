# Product Requirements Document (PRD)
**Version:** 0.1 | **Date:** 2026-11-04 | **Stage:** design baseline

## 1. Problem and objective
Operators running PVE need a predictable, secure and compact Android phone UI for infrastructure visibility and controlled guest operations without logging in via the desktop-centric web interface. The app is an API client, not a host hypervisor and not a replacement for the PVE web UI.

### Primary personas
- **Homelab operator:** 1–3 nodes, rapid status checks and safely start/shutdown guests.
- **Small-team administrator:** several clusters, least-privilege tokens, audit awareness, explicit action confirmation.
- **Read-only observer:** restricted PVE Auditor-like account, views status and never sees misleading enabled controls.

## 2. Goals, quality bars and out-of-scope
| ID | Goal | Measurement / acceptance |
|---|---|---|
| G01 | Android-only mobile product | Only `app/android` platform runner generated and tested; responsive phone widths 320–480dp |
| G02 | Secure local-first connection | HTTPS with server identity verification by default; explicit warned per-profile exception per [TLS option](40-profile-tls-option.md); no global TLS bypass |
| G03 | Reliable management | Mutations tracked to server task terminal state, failures visible |
| G04 | Least privilege | No assumed root permission; 401/403 recognized and explained |
| G05 | Proxmox compatibility | PVE 9.2 acceptance target; PVE 8.4 regression target with separate evidence |
| G06 | Operator clarity | Distinguish running/stopped/unknown, current vs stale data and node vs guest scope |
| G07 | No mandatory hosted infrastructure | Endpoint is user's cluster; no credentials pass through third-party service |

Not in v1: creating/deleting/migrating guests, editing storage/networking, backups/restores, Ceph mutation, HA policy updates, node reboots, Linux shell, console control, monitoring push notifications or Android tablet-specific mode. These can be independently assessed in later releases.

## 3. User stories and acceptance criteria
**US-01 Add a cluster:** Given an HTTPS PVE URL, token identifier and token secret, user sees test results; URL is normalized, unsafe scheme rejected, certificate mismatch surfaced. Saved secret remains device encrypted. Must handle timeouts, incorrect credentials and insufficient permissions distinctly.

**US-02 Browse resources:** Given one authorized cluster, user sees guest list grouped/filterable by node/type/status, with placeholders for missing fields. Hidden or permission-restricted objects are not assumed nonexistent. Rendering uses identifiers (`clusterProfileId`, `type`, `vmid`, `node`) rather than guest name as keys.

**US-03 Manage allowed guests:** When user chooses Start, Shutdown, Reboot, or Stop on a supported guest and confirms, UI submits once, shows submitted task ID and polls status. A task completing with error never displays a success snackbar. Stop/Reset are higher risk and require clearer copy.

**US-04 Multi-cluster:** Switching profile immediately stops old polling, cancels outstanding refreshes, isolates caches and credentials, and never dispatches a command to a stale profile.

**US-05 Limited privilege:** User with read-only rights can still view authorized resources; action attempts are blocked or rejected gracefully. No UI-only permission check is treated as enforcement.

**US-06 No network:** Last known non-sensitive data may be shown with timestamp and conspicuous stale status, but no mutation is attempted while disconnected.

## 4. Quantitative non-functional targets (proposed; measure before release)
- Cold launch to interactive shell: p95 < 2.5 seconds on agreed mid-range test phone (excluding cluster network latency).
- Dashboard fetch: no more than 1 normal refresh every 15 seconds while foreground; stop on background; task polls use bounded adaptive intervals.
- List smoothness: 60fps target at 200 guests via virtualization/lazy rendering; test without artificial caching of live statuses.
- Secret leakage: 0 credentials, tickets or VNC tokens in plaintext logs, screenshots of diagnostic dialogs, analytics, crash reports, or Git.
- Accessibility: screen reader labels for every icon action; >= 48dp touch targets; readable at Android font scale 200%; no color-only status.
- Error reporting: visible actionable state for offline, permission denied, task failure and TLS mismatch.

## 5. Dependencies and assumptions
PVE administrator provisions a limited token, working DNS/VPN, TLS trust (public CA/internal CA), a dedicated non-production PVE test environment, read/write test guests, and a role to verify permission denial. API response differences between PVE versions must be handled, not guessed away.

## 6. Release acceptance gates
No MVP release until all P0 requirements in scope have automated unit/widget tests, known-version integration tests, negative permission tests, SSL failure tests, checked Git secrets, and a signed Android test artifact. Details in [definition of done](19-definition-of-done.md).
