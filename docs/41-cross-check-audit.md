# Cross-check audit — 2026-11-04

> Historical evidence record. Test counts below describe this audit at the time it ran. The current whole-repository review and current scope are in [docs/45-full-implementation-cross-check.md](45-full-implementation-cross-check.md).

## Scope and assurance
Reviewed the complete current Flutter implementation (models, gateway, encrypted credential/profile storage, controller, lifecycle, navigation and UI), all test suites, Android generation/hardening scripts, both CI workflows, signing configuration and implementation/status documentation. This is a source and automated regression audit, not a claim that every defect is excluded or that the full premium roadmap is implemented.

## Findings corrected
- Malformed successful POST envelopes, JSON/unknown transport errors, cancellations, HTTP 408/5xx and mutation redirects now retain unknown-outcome safeguards rather than enabling unsafe retry. Explicit auth rejection remains distinct.
- Fractional/invalid guest identifiers are not silently coerced; non-finite numbers and out-of-range timestamps are handled safely; malformed inventory/storage/task rows are accounted for.
- Explicit HTTPS port 443 is preserved instead of being silently normalized to port 8006, including after saving/reloading. URL tests cover canonical IPv4/DNS/IPv6 origins and invalid ports. Existing profiles whose intended port was already lost should be removed and re-added rather than guessed/migrated.
- Profile metadata, vault and favorite mutations are serialized. Partial vault writes are rolled back where possible; a failed write does not poison the queue. Late favorites cannot recreate deleted-profile metadata.
- Deletion immediately disconnects an active profile, cannot reactivate a profile while its token is being removed, and cannot override a newer user-selected connection. Supplementary data is cleared too.
- Poll ownership is scoped to the connection generation; a hung old session cannot block or alter new-session tasks. Backgrounding during preflight blocks a late POST, resume refreshes inventory, disposal cancels late onboarding, and future-dated snapshots cannot authorize mutations.
- Guest routes capture the rendered profile scope. Credential/plugin exceptions are sanitized; disposed credential controllers are not accessed. Favorite write failures produce a user-visible error rather than an unhandled asynchronous exception.
- Narrow-screen/large-text layouts use scrollable guest headers/empty states and scalable dashboard cards. Missing guest metrics no longer animate indefinitely as if they were loading. Widget tests are not a substitute for physical TalkBack/font-scale coverage.
- Android hardening is repeatable; bootstrap restores the committed lockfile on generator failure. Flutter's template 8G heap is replaced with 2G Gradle/512M metaspace, two non-parallel workers and a 512M Kotlin daemon. Generated runner files, Python caches and private signing material stay outside tracked source.
- Release shell summaries preserve literal Markdown backticks; metadata is validated and successive workflow runs receive distinct versionCodes. Signing properties use an explicit Kotlin import, files are created privately and cleaned on failure, release signing is main-only, and verified APK certificate digests must match the configured key. Both workflows include offline delivery regression tests and pin Java 17.
- Corrected stale documentation that described favorites as unimplemented or required signing keys to be absent from protected GitHub Actions secrets. Per-profile TLS bypass remains an explicit user-approved security tradeoff, not trusted-certificate enrollment.

## Signing and repository checks
All four required Actions secret names are configured. The protected local recovery keystore matches its base64 record; both passwords open the private key and file/directory permissions are restricted. Values are never printed or committed. An independent encrypted off-machine backup is still the operator's responsibility. The repository is private and its default branch is `main`.

## Validation evidence
Validated using pinned Flutter 3.44.4 / Dart 3.12.2 with the unmodified committed dependency lockfile:
- Immutable Dart formatting and `flutter analyze --fatal-infos`: passed.
- All **57 Flutter unit/widget/native TLS tests**, with coverage output: passed.
- All **5 offline Python delivery tests**: passed (repeatable hardening/resource caps, bootstrap failure rollback, release summary, versionCode and signing cleanup/verification guards).
- Documentation/premium/source smoke checks, workflow YAML parsing, Bash syntax checks and Git whitespace checks: passed.
- Actual pinned Android runner generation in an isolated copy: package identity, manifest/signing hardening, repeated resource-cap enforcement, and application source/lockfile preservation verified. No local APK build was run; push-triggered GitHub Actions is the current-commit debug-build gate.
- Signing recovery consistency/private-key/password/permission checks and repository secret-name/private/default-branch checks: passed without exposing values. The staged changes are checked for the actual generated signing values before commit; this is not a comprehensive historical secret audit.

No manual release workflow is dispatched by this audit, and no signed release is published.

## Remaining release gates and intentionally deferred scope
- Real PVE 9.2/8.4 single/multi-node contracts, least-privilege ACL matrices, QEMU/LXC actions and network fault injection have **not** been executed here. Reviewing upstream task API source is not live-server verification.
- Physical Android min/current API TLS, private-CA/expired/wrong-host/IPv6, Keystore/backup/restore, process death, VPN switching, TalkBack and 200-guest performance/power tests remain open.
- Task tracking and unknown-outcome locks remain in-memory/session-only. There is no persistent operation journal across process death; inspect server task history before manually retrying after restart/reconnect. No offline/automatic mutation replay is implemented.
- Signed release APK execution, ABI/update/install verification, independent security/dependency/advisory/license/SBOM review and comprehensive repository-history secret scanning remain release gates. Configuring a key and testing workflow logic does not satisfy them.
- The implemented app remains the M1 safe-operation foundation plus a partial M2 cockpit. Profile-scoped named saved views and expanded local type/node/sort discovery were added after this audit. Charts/RRD, tag/group filters, alerts/background notifications, persistent offline cache, biometrics, ticket/MFA/console, snapshots/backups, migration/provisioning, PBS/PDM and infrastructure mutation remain intentionally deferred. The premium catalogue is a planning backlog, not proof those features exist.

See [Definition of Done](19-definition-of-done.md), [release gates](33-test-acceptance-release-gates.md) and [TLS policy](40-profile-tls-option.md). These open gates must not be described as "nothing missing" or production certification.
