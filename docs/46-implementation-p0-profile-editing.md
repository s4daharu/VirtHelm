# VirtHelm — P0 profile editing implementation

**Implemented:** 2026-11-04. **Scope:** F01 profile editing for the existing Flutter Android implementation.

## Implemented behavior

Saved Proxmox connections can now be edited from Settings without deleting and recreating the profile. The editor supports:

- connection alias changes;
- HTTPS endpoint changes using the same strict origin normalization as onboarding;
- certificate-verification policy changes, including the existing explicit warning/confirmation before saving an insecure TLS exception;
- API-token replacement; and
- keeping the existing encrypted token by leaving both token fields blank.

Every edit keeps the existing profile ID. Profile-scoped favorites and named guest views therefore remain attached to the same connection.

## Validation and persistence safety

An edit is not persisted merely because the form is valid. VirtHelm constructs a candidate gateway with the edited endpoint/TLS/token configuration and requires both the version request and inventory request to succeed before replacing local profile state.

Profile metadata and encrypted credentials are updated transactionally through the serialized repository mutation path. If credential or metadata persistence fails, the repository makes a best-effort rollback to the previous metadata and previous encrypted credential and reports the update as failed.

Supplying only one token field is rejected. Supplying both token fields replaces the credential only after connection validation. Leaving both blank reuses the existing secure-vault credential; if that credential is unavailable, the edit requires a replacement token instead of silently saving an unusable profile.

## Lifecycle and isolation

Editing an active profile reopens the session using the validated configuration and refreshes live inventory. If the active connection changes while validation is in flight, the generation guard cancels the stale edit before persistence. Editing preserves the profile ID and does not migrate or copy profile-local metadata to another connection.

## Automated coverage

The Flutter regressions cover:

- profile ID, favorite and saved-view preservation across edits;
- credential replacement under the same profile ID;
- rollback after a failed replacement credential write;
- controller validation with reuse of the existing credential;
- edit-form prefill and blank-token preservation; and
- rejection of a partial replacement token.

The repository's normal Docs and Android checks remain the merge gate: documentation/source smoke checks, generated Android hardening, immutable formatting, fatal-info analysis, Flutter tests and debug APK compilation must all pass on the final branch head.

## Remaining P0 and release gaps

This closes the source-level F01 profile-editing gap, but does not make the complete P0 MVP or a production release complete. Remaining documented gaps include user-facing server-version/capability presentation, rich task detail/logs, user-configurable theme/refresh/display preferences, persistent offline read caching, and general bounded automatic GET retry/backoff/full timeout-offline classification.

Live PVE 9.2/8.4 compatibility/ACL/mutation evidence, physical Android security/accessibility/performance verification, signed install/update/rollback evidence, dependency/SBOM/license/advisory review, repository-history secret scanning and independent security review remain external release gates.
