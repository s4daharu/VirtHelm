# Security Policy

VirtHelm now contains an executable Flutter Android implementation, but **no production security assurance or release certification is claimed**. Do not report vulnerabilities in public issues. Use GitHub Private Vulnerability Reporting if it is available for this repository; otherwise contact the maintainer through a private channel before sharing details. Never post PVE credentials, private infrastructure URLs, CA private keys, signing material, or sensitive task logs in issues.

Certificate verification is enabled by default. Users can explicitly disable it per connection for any HTTPS host, after confirming the exact origin and impersonation/token-theft risk. The option persists and insecure profiles remain visibly marked. There is no global bypass or automatic fallback; HTTPS and redirect blocking remain mandatory. This exception sacrifices server authentication even on a LAN and is not recommended for production. See `docs/40-profile-tls-option.md`.

The project rejects cleartext fallback, embedded/default root credentials, hidden uploads, automatic retry of potentially executed mutations, cross-profile resource reuse, debug-key release signing, and unsupported console-auth claims. API-token console access remains out of scope.

Current automated protections include HTTPS-only endpoint validation, redirect rejection, secure token storage, Android backup/cleartext hardening, release-runner assertions, mutation single-flight/unknown-outcome guards, profile-generation isolation, and negative unit/contract tests. These controls do **not** replace PVE 8.4/9.2 lab tests, physical-device TLS/backup testing, dependency/security review, or release signing.

See `docs/07-security-auth.md`, `docs/19-definition-of-done.md`, and `docs/39-implementation-audit.md`.
