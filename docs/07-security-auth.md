# Security Architecture, Authentication, Threat Model

## Primary security rule
This client controls real infrastructure. Strict TLS defaults, authorization boundaries and secret handling are release blockers. **Never implement a global TLS bypass, automatic insecure fallback, plain HTTP, embedded long-lived root password, or public port 8006 exposure as default or suggested production paths.** The user-requested per-profile insecure exception is defined in [TLS option](40-profile-tls-option.md) and supersedes earlier blanket prohibitions in planning documents. It is not recommended for production.

## Authentication modes
### MVP — API token (recommended for ordinary read/control APIs)
- A PVE administrator creates `USER@REALM!TOKENID` and secret, gives explicit ACLs and an expiration date. By default separated-token privileges intersect the user's privileges.
- Pass `Authorization: PVEAPIToken=USER@REALM!TOKENID=SECRET` on each authorized PVE API call. Secret is shown only at token creation; if lost, rotate.
- No CSRF token is required for API token requests. Do not put tokens in URL, crash logs or query strings.
- A login test should verify `/version` and a permitted inventory endpoint; `version` alone does not establish permission to read VMs.
- Token scopes should be customized to role and resource path. Example **policy intent**, not paste-ready ACL commands: observer can audit only; power operator gets minimum VM power privileges on specific `/vms/<vmid>` paths, as checked in PVE API permission requirements. Prefer per-cluster user account over `root@pam` tokens.
- **Official limitation:** PVE API tokens cannot be used for VM/system consoles. NoVNC is not an API-token MVP feature.

### P1 — ticket-based user session (requires careful design)
- Start user login via `POST /access/ticket` and server-supported MFA/realm challenge flow; do not encode a one-size-fits-all TOTP handshake without live verification.
- Use `PVEAuthCookie` cookie for authenticated calls and `CSRFPreventionToken` header for state-changing requests. Treat tickets as temporary secrets; refresh/relogin on expiry and revoke memory state on logout.
- Never store raw password after login; consider biometric re-entry only to unlock locally encrypted credentials, **not** as proof of PVE server login.
- WebSocket console endpoints need an authenticated browser/client context and their own short-lived VNC tickets; P1 auth does not automatically finish P2 console architecture.

## Transport and certificate strategy
1. Default: validate server certificate using normal Android/OS trust plus hostname. Recommend a real trusted cert or organization's internal CA distributed securely to device.
2. Prefer securely enrolled trust for an internal CA/self-signed certificate. Runtime per-host CA/certificate enrollment remains future work. Users may instead explicitly disable verification per profile after a warning and origin-specific confirmation. This saved opt-in accepts invalid chains, expired certificates and hostname mismatches for that client's exact host/port; it does not authenticate the server. Never apply it globally or as automatic fallback.
3. Android network config should disallow cleartext traffic. Debug-only CA support may be configured in debug builds, never release-wide exception.
4. Certificate pinning is not automatically “more secure”; it creates rotation risk. If implemented, require out-of-band verification, backup/rotation plan and no silent trust-on-first-use claim.
5. Recommend VPN/private network reachability (e.g. WireGuard or managed VPN). Avoid forwarding PVE HTTPS port 8006 directly to the public Internet.

## Threat model (STRIDE-oriented)
| Threat | Attack/impact | Control and test |
|---|---|---|
| Spoofing | Fake PVE server/MITM | verified TLS hostname/CA by default; insecure opt-in sacrifices this protection and must remain visibly marked; adversarial proxy test |
| Tampering | Modified requests/action replay | HTTPS, single-flight mutation, explicit confirm, no write retry on timeout |
| Repudiation | Unclear initiator of critical action | local non-secret action metadata/task UPID, server logs; no false audit claims |
| Information disclosure | Exfiltrated token, guest names, task logs | Keystore storage, log redaction, no third-party tracking, cleanup and secure backup policy |
| Denial of service | polling overload or failing server | max concurrency, backoff, foreground-only poll and user control |
| Elevation of privilege | broad token rights, insecure shared session | role-scoped token, no default root, isolate profile/auth and enforce server ACL |
| Stolen device | cached credentials allow actions | encrypted secrets, app lock optional, Android device screen lock, fast revoke instructions |
| Malicious backup | Android restore of encrypted secrets w/o key | disable app auto-backup or exclude credential storage; verify on device |

## Storage and screen capture
Use `flutter_secure_storage` with Android Keystore-backed implementation compatible with chosen version. At the time of research current package major versions have Android min/compile SDK requirements and breaking crypto migration. Pin a compatible tested version after Android build; follow package's backup-exclusion guidance. Use `FLAG_SECURE` selectively for credential screens if UX/policy warrants; avoid screenshots of secrets. In-memory secret material cannot be perfectly eliminated in Dart garbage-collected runtime; shorten lifetime and never stringify secrets.

## Secure input and request handling
- Permit `https` URLs only, explicit host/port, reject username/password-in-URL, reject redirects to unexpected hosts (especially redirects carrying Authorization), bind all calls to profile origin.
- Validate action type (`qemu` vs `lxc`), VMID range and URL path segments. Never compose raw arbitrary user strings into request paths without escaping.
- CSRF applies to ticket-auth state mutations; don't invent CSRF bypasses.
- Avoid sending telemetry/errors to any vendor by default; opt-in diagnostics must redact credentials, cookies, URLs with token segments and task logs.
- Secrets may appear in PVE task logs; never sync them or include in a support bundle by default.

## Security verification and incident playbook
Static scans (gitleaks or equivalent), Android network-config release build inspection, proxy TLS-failure test, backup/restore test, rooted-device limitations documented, secret grep on logs, 401/403 and expired-token tests, session expiration tests, device-loss token revocation procedure. The administrator revokes leaked token in PVE and replaces it; user removes profile and clears cached data.

## Sources
PVE user management/token restrictions: https://github.com/proxmox/pve-docs/blob/master/pveum.adoc  
Android transport guidance: https://developer.android.com/privacy-and-security/security-config  
Secure storage package requirements: https://pub.dev/packages/flutter_secure_storage
