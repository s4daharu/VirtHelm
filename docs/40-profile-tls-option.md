# Per-connection insecure TLS option

## Policy and usage
Certificate and hostname verification remain enabled by default. To use a self-signed lab server, **Add connection → Disable certificate verification → Connect (insecure)**. Confirmation shows the normalized HTTPS origin and warns about token theft, impersonation and command tampering even on a local network. Cancelling sends no connection request. The option is available for any host, not just private addresses, as explicitly requested by the user.

The choice is saved with that profile and used for future sessions, including inventory, task reads and guest operations. No repeated confirmation is required when reopening an already saved profile. Active shell tabs and guest details show an insecure warning; connection menus and settings mark opted-in profiles. Guest action confirmations also mention the exception. To restore verification, remove and re-add the connection with the switch off; profile editing/trust enrollment is not implemented.

Prefer a trusted certificate and VPN. HTTPS without certificate verification encrypts traffic but does **not** establish server identity; a LAN is not proof of trust. This option is not recommended for production.

## Implementation boundaries
- `ConnectionProfile.allowInvalidCertificates` defaults to `false`. Old metadata and non-boolean values cannot enable it.
- A new native Dio/HttpClient adapter belongs to each opted-in gateway. Its bad-certificate callback accepts only the selected endpoint's exact host and port. No global `HttpOverrides` or Android-wide trust exception is used.
- Strict profiles retain normal platform validation, including after switching from an insecure profile.
- HTTPS-only endpoint validation, no embedded credentials, redirect rejection, encrypted token storage and existing mutation guards are unchanged. There is no retry with insecure TLS after a strict connection fails.
- This does not remove the requirement for an HTTPS server/certificate, add HTTP support, or securely enroll/pin a certificate.

## Verification and release gates
Regression coverage includes metadata defaults/migration, explicit opt-in persistence and profile isolation, onboarding cancellation/confirmation, active warnings, native self-signed/wrong-host rejection by default and acceptance only on opt-in, exact-host/port callback checks, and redirect blocking. Native tests use OpenSSL-generated ephemeral certificates/keys; no real credentials or keys are checked in.

Physical Android tests, trusted/expired/wrong-host/private-CA matrices, VPN/network switching and independent security review remain required before release. Tests do not prove a network is trustworthy or restore server authentication when bypass is selected.

Initial validation used Flutter 3.47.5 in an isolated source copy. The subsequent [cross-check audit](41-cross-check-audit.md) verified the analyzer and all 57 tests on pinned Flutter 3.44.4 / Dart 3.12.2 with the unmodified committed lockfile, plus actual Android runner generation. CI APK/device/release gates remain separate.

This user-approved policy revises ADR-005 and supersedes earlier blanket no-bypass statements in the original product/premium planning documents. Future ticket/console/PBS/PDM transport policies remain separately gated, not implicitly opted in by this REST profile setting.
