# Whole-repository cross-check — 2026-11-06

This report records a source, test, CI, pull-request and repository-state cross-check of VirtHelm after the node RRD milestone. It is an implementation audit, **not** live Proxmox VE compatibility evidence, physical Android certification, or production release approval.

## Audited baseline

- Baseline `main`: `adfd0ab4976f901f59f0eee3a6515c79e036681e` (`feat(metrics): add bounded node RRD performance history (#28)`).
- The baseline main push passed **Docs and Android checks** run 42158168497: documentation/source/delivery checks, generated Android hardening, lockfile integrity, pinned Dart formatting, analyzer, the full Flutter suite, and debug APK build.
- The source contains 144 Flutter test declarations after the audit regressions in this branch; `PROJECT_STATUS.json` is kept in sync with that count.
- The release workflow remains prerelease-only and separately re-runs repository checks before restoring release signing material, building ARM64/ARMv7 APKs, checking signatures/ABIs, and publishing directly to GitHub Releases.

## Pull-request cross-check

PR #25, **feat: add local guest tag browsing**, was still open during the audit. It was based on the pre-RRD integration main, contained an older tag-only design and an obsolete version bump, and was superseded by the broader tag+pool implementation merged through PR #27. PR #25 was therefore closed unmerged during this audit. No code from it is required to preserve current HOME-007 behavior.

All newer completed milestones (#26 guest RRD, #27 tag/pool browsing, #28 node RRD) are present on the audited main line.

## Source and safety cross-check

The audit reviewed the current controller, gateway, profile persistence, offline counts, connectivity bridge, filtering/saved views, task details, guest details, node details, workflows and delivery guards.

Confirmed boundaries include:

- HTTPS-only canonical direct PVE origins; redirects disabled.
- TLS verification enabled by default; the explicit insecure exception remains scoped to one profile's exact host and port.
- API tokens remain in Android secure storage; ordinary SharedPreferences hold only non-secret metadata/preferences and the opt-in aggregate offline-count snapshot.
- Idempotent GET retries remain bounded; mutation POSTs are never automatically replayed.
- Guest actions require a fresh clean inventory, exact current guest identity, live preflight state, single-flight reservation and conservative unknown-outcome lockout.
- Terminal UPIDs do not unlock writes until a later authoritative inventory refresh.
- Task logs remain on-demand, bounded to 100 rows per page / 500 viewable rows total and are not persisted.
- Guest/node RRD history remains explicit, GET-only, bounded to 1,500 locally considered rows, transient, and profile/generation isolated.
- Tag/pool browsing remains presentation-only over existing inventory; malformed optional metadata cannot authorize a mutation.
- No TODO/FIXME/unimplemented stubs or debug-print logging were found in the current application source. The only certificate callback is the documented profile-local exact-origin exception.

## Audit fixes

Two consistency gaps were corrected.

First, task-detail inspection did not short-circuit when the Android default-network observer had already reported `unavailable`, while refresh and guest/node RRD inspection did. Task, guest and node on-demand reads now all refuse new I/O in that state.

Second, an observed HTTP 401 from an on-demand task or RRD read cleared the optional offline counts but did not immediately mark the current live inventory authorization state unsafe. All three on-demand read families now record the authentication failure in controller state, purge/hide cached counts and keep writes disabled until a clean authenticated refresh succeeds.

Regression coverage checks both behaviors without changing the POST single-shot rule, GET retry bounds, background behavior or persistence model.

## Verification-record fixes

Historical `PROJECT_STATUS.json` entries still described several already-merged milestones as awaiting exact-head/final CI. Those entries are reconciled to **source implemented + CI passed + live validation pending**. This does not convert synthetic/CI evidence into live PVE or device evidence.

The documentation smoke checker previously covered implementation notes only through doc 54. It now includes docs 55–62, so the newer task, I/O, session-isolation, RRD, tag/pool and this cross-check report are checked for existence, H1 structure and local-link validity. It also parses `PROJECT_STATUS.json` and checks the expected test-count field.

## Remaining gates and deliberate omissions

The following remain open and must not be inferred from green repository CI:

- sanitized live PVE 9.2 and 8.4 endpoint/payload/ACL fixtures, including RRD/tag/pool/task/storage behavior;
- physical Android tests for TLS, secure storage/backup, airplane mode/LAN/VPN transitions, lifecycle races, TalkBack, large text and performance;
- independent dependency/security review and production-release approval;
- branch-protection/ruleset enforcement (the repository currently reports `main.protected=false`);
- deferred premium scope such as richer storage/capacity history, alerts, persistent guest/detail offline cache, topology/group views, console, backup/restore and infrastructure mutation.

## Branch cleanup boundary

Historical feature, verification and Dependabot branches have no remaining open pull request after PR #25 was closed. They are operational cleanup candidates once the audited source is merged. Branch deletion does not alter application correctness and must preserve `main`.
