# Security Policy

This repository is a **design-only** preimplementation package. No shipping app/security assurance is claimed. Report a vulnerability privately to the repository maintainers using a privately agreed secure channel (or a repository security advisory mechanism only if actually available), not a public issue. Do not post PVE credentials or real infrastructure URLs in issues. If a token is exposed, revoke it in the PVE administration interface and rotate immediately.

We will not accept pull requests adding TLS verification bypass, default root passwords, embedded auth secrets, hidden uploads, silent insecure downgrade, automatic retries of potentially destructive operations, or unsupported claims of console auth. Security gates: see `docs/07-security-auth.md` and `docs/19-definition-of-done.md`.
