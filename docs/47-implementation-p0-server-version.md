# VirtHelm — P0 server version retention and presentation

**Implemented:** 2026-11-04. **Scope:** the server-version portion of F02 for the existing Flutter Android implementation.

## Implemented behavior

VirtHelm now retains the last successfully observed Proxmox VE server version as non-secret connection metadata and presents it to the operator.

- New connections store the version returned by the validated `/version` request.
- Connection edits replace the stored version only after the edited endpoint/TLS/token combination passes the same version and inventory validation used by onboarding.
- Activating a saved connection performs a fresh `/version` read and updates the stored last-observed value when it changes.
- The active app-bar subtitle shows `PVE <version>`.
- Settings shows `PVE <version> (last observed)` for each connection.
- Profiles created before this change remain readable; they show no observed version until a successful activation refreshes the metadata.

The value is profile metadata only. API credentials remain in the encrypted credential vault.

## Validation rules

A successful version response must contain a non-empty string of at most 80 characters after trimming. Missing, blank, oversized or non-string stored metadata is not treated as a valid observed version. The live gateway fails the version check when the server response does not provide a usable version.

Version metadata updates use a serialized metadata-only repository path and do not rewrite the encrypted token. If refreshing the local version metadata fails after a successful live version read, the live observed version remains available in memory for the active session; the connection is not failed solely because this secondary metadata could not be persisted.

## Compatibility boundary

The displayed value is deliberately labelled **last observed**. It is not a statement that a given PVE release has passed VirtHelm's compatibility matrix, and this change does not introduce automatic feature gating from a version string.

Release claims still require the documented real-server PVE 9.2 primary and PVE 8.4 regression evidence, ACL coverage, mutation/fault-injection checks, and physical Android verification. Unknown future versions are not automatically declared supported merely because the `/version` endpoint is readable.

## Automated coverage

Regressions cover:

- server-version metadata round-trip and malformed persisted values;
- missing/blank live version responses failing validation;
- onboarding persisting the observed version;
- activation refreshing a changed version without rewriting profile identity; and
- app-bar/Settings presentation of the last-observed version.

The final branch head remains merge-gated by the repository's complete Docs and Android checks workflow: source/document smoke checks, generated Android hardening, dependency lockfile integrity, immutable formatting, `flutter analyze --fatal-infos`, Flutter tests and Android debug APK compilation.

## Remaining P0 and release gaps

This closes the source-level F02 server-version retention/presentation gap. Remaining documented P0 implementation gaps include rich task detail/log exploration, user-configurable theme/refresh/display preferences, persistent offline read caching, and general bounded automatic GET retry/backoff with fuller timeout/offline classification.

Live PVE 9.2/8.4 compatibility evidence and the physical-device/release/security gates remain open.
