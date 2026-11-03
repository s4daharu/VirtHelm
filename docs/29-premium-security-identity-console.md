# Premium Security, Identity, Trust and Console Controls
**Release blocker:** VirtHelm administers production-capable infrastructure. Security is mandatory for all features, not a paid tier. Baseline detail lives in [07-security-auth.md](07-security-auth.md) and [08-console-rfc.md](08-console-rfc.md).

## Threat inventory
Assets: PVE/PBS/PDM bearer tokens; user-session cookies and CSRF tokens; console tickets; network origins; TLS trust decisions; cached infrastructure names; backup metadata; action approvals; local app state. Actors: device thief, malicious Android app/overlay, hostile Wi-Fi/VPN network, compromised reverse proxy, malicious QR/deep link, compromised plugin/CI dependency, over-privileged operator. Risks: account takeover, unexpected VM shutdown, cluster outage, unauthorized backup deletion, silent MITM, cross-site data leak, credential exposure through logs or Android backups.

## Auth adapter rules
| Strategy | Allowed use | Constraints |
|---|---|---|
| PVE API token | ordinary PVE REST inventory/mutations where ACL permits | proper PVEAPIToken header, scoped to profile; no console access |
| PVE user ticket | normal API and separate console flows if proved | PVEAuthCookie and CSRFPreventionToken for state-changing requests, MFA/realm challenge support, expiry |
| PBS auth | PBS API only | independently verify header/cookie/CSRF and rights |
| PDM auth | PDM API only | independently verify own auth and privileges |
| Local biometric | unlock local encrypted app state or gate write UI | not substitute for remote authentication or ACL |

## Security state machine
Unconfigured -> Connecting -> TLSVerified -> Authenticated -> ACLProbed -> Ready/ReadOnly/Restricted; on certificate change enter **TrustChanged** and block authenticated requests pending user out-of-band verification. On 401/expired ticket: stop authenticated actions, clear session-only secret and prompt reauth. On 403: keep allowed read access, don't “fix” by requesting root token.

## TLS and key storage
- HTTPS only and origin-bound Authorization; reject unexpected redirects, credential-bearing URLs, self-signed bypass, wrong host, expired and downgraded certificate.
- System CA + hostname verification by default; optional manual per-host CA/certificate trust only through explicit pin/CA enrollment with fingerprint checked out-of-band and rotation recovery; avoid “trust any cert” even during onboarding.
- Use Android Keystore-backed storage; reviewed stable flutter_secure_storage integration, no keys/secrets in SharedPreferences or plaintext files.
- Secure Android backup exclusions, storage migration after Android restore, profile deletion erasure, backup/restore and passcode reset testing.
- Session secrets never in logs, crash reports, clipboard, notifications, exported diagnostics, analytics, cross-profile provider state or deep links.
- “Biometric app lock” should cryptographically gate access where feasible, use OS biometric prompt and device credential fallback under an explicit threat model. A cosmetic boolean flag is insufficient.
- Sensitive notifications hide guest/host names on lock screen; optional screenshot protection on auth/console screens.

## Console protocol RFC gate
1. Enumerate QEMU VNC and LXC terminal endpoints/versions/ACL separately in PVE viewer.
2. Confirm actual ticket auth including MFA, console short-lived ticket, CSRF/HTTP handshake, WebSocket Origin/Host and TLS path on Android real devices.
3. Select a vetted maintained client (noVNC-based isolated WebView vs native VNC); audit JS bridge exposure, iframe origins, clipboard, WebView storage, file access and browser redirects.
4. Never display “console available” for token-only profile. Expired credentials must terminate session, disconnect websocket, scrub memory and never auto-replay actions.
5. Test virtual keyboard, Ctrl/Alt/Delete keys, Android IME, clipboard consent, high-DPI scaling, landscape, tunnel/VPN reconnection and lock-screen privacy.

## Permission model and privileged UI
Server is final authority. Capability registry combines server version, current auth mode, ACL probe, feature gate, online state, operation risk and freshness. For R2+ actions, require explicit preflight. For R3/R4, use elevated confirmation; consider an optional policy that requires reauthentication for each operation. **No client control claims to bypass or replace PVE ACL.**

## Supply chain and data governance
Dependency SBOM, license scanning, pinned lockfile, signed release, CI least privileges, no secrets in source/fixtures, provenance of external VNC WebView assets, security advisory process. Privacy disclosure enumerates collected data and remote endpoints. No vendor telemetry by default; diagnostics opt-in and scrubbed. Periodic OWASP MASVS and MASTG audit, plus independent mobile penetration test before production-grade claims.

## Mandatory attack tests
MITM/hostname mismatch, same domain different certificate, redirect exfiltration, cross-profile token mixing, corrupted encrypted data, locked device, notification leaks, missing/weak biometrics, expired PVE tickets, server restarts, hostile task logs, HTTP WebSocket upgrade misuse, non-ASCII endpoint and redirection, rooted-device limitations and 2FA challenge variants.

## Sources
https://github.com/proxmox/pve-docs/blob/master/pveum.adoc
https://cheatsheetseries.owasp.org/cheatsheets/Mobile_Application_Security_Cheat_Sheet.html
https://mas.owasp.org/MASVS/
https://developer.android.com/privacy-and-security/security-config
