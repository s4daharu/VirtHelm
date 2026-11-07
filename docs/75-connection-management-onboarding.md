# Connection management and staged onboarding

This milestone implements the dedicated connection-management surface already
planned by the VirtHelm UX documents. It is source-level and automated-test
evidence only; live PVE and physical Android validation remain separate release
gates.

## Scope

- A dedicated **Connections** page now owns saved-profile management instead of
  rendering every profile inside Settings.
- Saved profiles expose their endpoint, last-observed PVE version, TLS policy
  and current in-memory state, with explicit **Use**, **Test**, **Edit** and
  **Remove** actions.
- Connection tests are read-only. They check the configured HTTPS origin,
  retrieve the PVE version and then attempt cluster inventory access.
- A version-success/inventory-401-or-403 result is shown as limited access
  rather than being confused with an unreachable server or TLS failure.
- Testing a saved profile may refresh its last-observed PVE version metadata,
  but does not rewrite the encrypted API token or activate that profile.
- When saved profiles exist but no valid active selection is persisted, startup
  now shows an explicit connection chooser instead of silently selecting the
  first profile.
- Add/edit onboarding is staged as **Server → API token → Verify**. The final
  save remains disabled until the explicit read-only inventory check succeeds.
- Saving still runs the existing controller validation again, so a stale UI
  check result cannot authorize a changed origin, TLS policy or credential.
- Settings now links to the dedicated manager, while the shell profile switcher
  retains quick switching and adds a direct manager entry.

## Credential and safety boundaries

- API credentials remain in the existing encrypted credential vault. The new
  verification result contains only PVE version, inventory accessibility,
  counts, TLS-policy state and sanitized failure metadata.
- Blank token fields while editing still mean “keep the saved token”; a partial
  replacement remains invalid.
- Disabling certificate verification still requires explicit confirmation
  before every network attempt. A successful insecure check is labelled as
  **TLS UNVERIFIED** and never claims server identity verification.
- Connection checks perform only the existing version and inventory reads. They
  do not submit guest actions, create task writes or alter retry policy.
- Profile deletion, profile identity preservation, metadata-only version
  updates, connection-generation isolation and guest-write freshness guards are
  unchanged.

## Automated verification

Coverage added for:

- read-only candidate verification with a 403 inventory result and no local
  persistence;
- saved-profile testing updating version metadata without rewriting credentials;
- startup chooser state when profiles exist without an active selection;
- staged onboarding, verification-before-save and partial token validation;
- insecure TLS confirmation before both test and save attempts;
- dedicated manager navigation, version/TLS metadata and read-only test action;
- narrow 320dp layout at 200% text scale.

The exact-head GitHub Actions run remains authoritative for Dart formatting,
analysis, Flutter tests and Android debug compilation.

## Remaining gates

This milestone does not claim physical-device or live-server completion.
TalkBack, 360/393/412dp device screenshots, secure-storage behavior on real
Android, certificate/VPN transitions and live PVE 9.2/8.4 permission fixtures
remain required. AMOLED/high-contrast/reduced-motion work and native biometric,
notification, widget and shortcut surfaces remain later milestones.
