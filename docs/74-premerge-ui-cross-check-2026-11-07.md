# Pre-merge UI and repository cross-check — 2026-11-07

This report records a pre-merge cross-check of the UI-overhaul branch against `main`. It is an implementation and local-CI audit, **not** live Proxmox VE compatibility evidence, physical Android certification, or production release approval.

## Audited baseline

- Baseline `main`: `2494a0b` (`feat(alerts): add foreground rule duration and hysteresis (#31)`).
- Audited branch: `feat/ui-overhaul-foundation-20261107`, commits `27ec0d6` through `1459b2c`, plus the cross-check fixes recorded in this report.
- The branch changes UI presentation, local filter state, the alert-rule editor and docs; it does not change PVE endpoints, gateway transport, credential storage, profile persistence or mutation semantics.

## Checks performed

- `git diff --check` and lockfile integrity: clean; `app/pubspec.lock` is unchanged from `main`.
- `python3 scripts/check_docs.py`: passed.
- `python3 scripts/check_source.py`: passed, including version/display-string synchronization and existing security/transport assertions.
- `python3 scripts/check_premium.py`: passed.
- `python3 -m unittest discover -s scripts/tests -v`: 14 delivery tests passed.
- `dart format --output=none --set-exit-if-changed lib test`: no changes.
- `flutter analyze --fatal-infos`: no issues.
- `flutter test`: 162 tests passed.
- `python3 scripts/check_android_generated.py`: generated-runner hardening checks passed.
- Android debug APK build: the local build was attempted with Java 17 and the hardened generated runner. It stalled for over ten minutes on an external Gradle artifact download with no file progress and was stopped. No local APK-build claim is made; the pinned-toolchain CI debug build remains the compile gate.

The local Flutter SDK is newer than the repository-pinned CI SDK. Exact-head CI on the pinned toolchain remains authoritative.

## Findings and fixes

The cross-check found and corrected these presentation/documentation gaps:

1. The shell subtitle could render a duplicate “No connection” label when no profile was active. Freshness is now omitted when there is no profile.
2. A sort-only guest-view change did not expose the local “Clear filters” action because sort was missing from the active-filter predicate. Sort is now included while the quick status chips remain independent.
3. The guest bottom action bar relied on a theme card color that can be null under an alternate theme. It now falls back to the surface color.
4. The storage capacity row could crowd its percentage at large text sizes. The value is now flexible and end-aligned.
5. The threshold target picker could sit under the keyboard. It now reacts to view insets, uses safe area, and the editor stacks its Cancel/Save actions at large text scale.
6. `docs/66` and `PROJECT_STATUS.json` still said the rule editor exposed only 1–5 samples and 0–10 percentage points. The editor now exposes the core-supported 1–10 samples and 0–20 points; both records are updated.
7. Earlier UI notes listed already-completed slices as future work. Their “remaining work” sections now list only the genuinely outstanding items: connection management, AMOLED/high-contrast themes, app lock/biometrics, notification surfaces, golden/device screenshots and physical Android validation.

## Safety invariants preserved

- HTTPS-only endpoints, redirect blocking, profile-local TLS exception and default certificate verification are unchanged.
- Guest writes still require exact profile/node/kind/VMID identity, a fresh clean inventory, live preflight, per-guest single-flight and conservative unknown-outcome lockout.
- Profile/generation checks still discard obsolete detail-editor and mutation results.
- Task logs remain on-demand, bounded, ephemeral and non-persistent.
- Threshold rules remain profile-scoped non-secret local metadata with foreground-only evaluation; no background worker or notification delivery is added.
- No API, credential, persistence or POST-retry behavior changed.

## Remaining gates

- Physical Android TLS/secure-storage/airplane-mode/VPN/lifecycle/TalkBack/200%-text/touch-target/performance validation.
- Sanitized live PVE 9.2 and 8.4 fixtures, including ACL and RRD/task/storage behavior.
- Independent dependency/security review and production-release approval.
- Branch-protection/ruleset enforcement remains an administrative follow-up; repository CI is not a substitute.
- Dedicated connection management, AMOLED/high-contrast themes, app lock/biometrics, notification surfaces and golden screenshots remain future UI work.

## Android debug build

The local debug APK build did not complete because Gradle stalled on a remote artifact download; it is not counted as verification. The pushed commit is gated by the repository CI debug-APK build on the pinned Flutter 3.44.4 toolchain. No APK is retained as an Actions artifact; release publication remains a separate signed prerelease workflow.
