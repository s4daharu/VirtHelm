# Security Policy

VirtHelm now contains an executable Flutter Android implementation, but **no production security assurance or release certification is claimed**. Report vulnerabilities privately to the repository maintainers or through a repository security-advisory mechanism if enabled. Never post PVE credentials, private infrastructure URLs, CA private keys, signing material, or sensitive task logs in issues.

The project rejects TLS verification bypasses, cleartext fallback, embedded/default root credentials, hidden uploads, automatic retry of potentially executed mutations, cross-profile resource reuse, debug-key release signing, and unsupported console-auth claims. API-token console access remains out of scope.

Current automated protections include HTTPS-only endpoint validation, redirect rejection, secure token storage, Android backup/cleartext hardening, release-runner assertions, mutation single-flight/unknown-outcome guards, profile-generation isolation, and negative unit/contract tests. These controls do **not** replace PVE 8.4/9.2 lab tests, physical-device TLS/backup testing, dependency/security review, or release signing.

See `docs/07-security-auth.md`, `docs/19-definition-of-done.md`, and `docs/39-implementation-audit.md`.
