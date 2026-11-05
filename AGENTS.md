# Repository guidance

## Scope and wiring
- `app/` is the only Flutter package; Android phones only. `app/lib/main.dart` creates `ProfileRepository` and a `ChangeNotifier`-based `AppController`; widgets observe it with `AnimatedBuilder`.
- `AppController` owns connection generations, foreground refresh, mutation guards and UPID polling. Route PVE I/O through `PveGateway` (`app/lib/core/pve_api.dart`), not directly from widgets.
- `ProfileRepository` serializes local writes: credentials go through `CredentialVault` into secure storage; profile metadata, favorites, saved views and app preferences use SharedPreferences. Metadata-only changes must not rewrite credentials.
- Use `PROJECT_STATUS.json` and implementation/audit docs for current scope. `docs/21`–`docs/36` and `docs/premium-feature-catalog.csv` are proposals, not implemented-feature evidence. Synthetic tests/debug builds do not establish live PVE 9.2/8.4 compatibility or production certification.

## Versioning
- `app/pubspec.yaml` is the version source of truth: `version: MAJOR.MINOR.PATCH+BUILD`.
- The displayed app version follows standard `MAJOR.MINOR.PATCH` semver. Bump it on every change; there is no single-digit limit on `MINOR` or `PATCH` (e.g. `1.9.9` → `1.9.10`).
- Android `versionCode` is independent of semver and Git history and must increase for every published update; Android rejects lower codes. The release workflow currently computes it as the pubspec `BUILD` plus `GITHUB_RUN_NUMBER`; preserve monotonicity when changing either source.
- Do not hand-maintain version numbers in the generated `app/android/` Gradle files. Local builds use pubspec metadata; CI passes explicit `--build-name` and `--build-number`. Full Git history is not needed for versioning, but local builds do not automatically receive CI's incremented code.

## Setup and verification
- Pin Flutter **3.44.4** (`app/.flutter-version` and CI); Android builds use Java **17** and an Android SDK. The TLS test also requires `openssl` and loopback sockets, not a live PVE server.
- From the repo root, run `bash scripts/bootstrap_android.sh` before the first Android build. It generates the ignored `app/android/` runner, applies hardening and resolves dependencies with `--enforce-lockfile`. Keep `app/pubspec.lock` committed; do not refresh it incidentally.
- Put persistent native changes in `scripts/harden_android.py` (and its regression tests), not just in the ignored runner. It enforces minSdk 26, INTERNET permission, no backup/cleartext, no debug-key release signing and Gradle/Kotlin resource caps.
- Fast offline CI checks, from the repo root (Python standard library; no Flutter required):
  ```sh
  python3 scripts/check_docs.py
  python3 scripts/check_premium.py
  python3 scripts/check_source.py
  python3 -m unittest discover -s scripts/tests -v
  ```
- Flutter CI sequence, from `app/` after bootstrap:
  ```sh
  git diff --exit-code -- pubspec.lock
  python3 ../scripts/check_android_generated.py
  dart format --output=none --set-exit-if-changed lib test
  flutter analyze --fatal-infos
  flutter test --coverage
  ```
- Focus a Dart suite from `app/` with `flutter test test/controller_test.dart` (substitute another test file). Controller tests inject `GatewayFactory` and fake `CredentialVault`; API tests inject Dio adapters. Keep regressions synthetic and credential-free.
- `check_source.py` asserts literal source strings, and delivery tests extract release steps by exact YAML step names. Refactors/renames may need corresponding assertions updated; these smoke checks do not replace Dart tests or Android compilation.

## Build limits on this machine
- Never run uncapped Flutter/Gradle builds or overlap builds. From `app/`, use `ionice -c3 nice -n 19 taskset -c 0-2 flutter build apk --debug`; use release only when requested. Announce the project/command and run builds expected to exceed 30 seconds in the background.
- Preserve hardening caps: Gradle heap 2048 MB/metaspace 512 MB, two workers, parallel off, Kotlin daemon 512 MB. After building, stop daemons from `app/android/` with `./gradlew --stop`; do not raise machine-wide limits.

## Safety invariants
- Async connection work must validate profile ID and connection generation before applying results; a reconnect to the same profile is still a new session. Preserve disposal/profile-switch race checks and close obsolete gateways.
- Guest writes require exact profile/node/type/VMID identity, a fresh clean inventory, live status preflight and per-guest single-flight through task completion. Never automatically replay POSTs. Ambiguous outcomes stay locked; terminal UPIDs require an authoritative inventory refresh begun after completion.
- GET retries are bounded to three attempts for transient failures; do not retry TLS, redirects, auth/permission failures or closed gateways. Timed refresh is foreground-only.
- HTTPS and redirect blocking are mandatory. The only certificate bypass is explicitly confirmed, persisted per profile and restricted to its exact host/port in `DioPveGateway`, with visible warnings; never use global `HttpOverrides` or automatic TLS fallback.
- Task logs are on-demand, bounded and ephemeral; never persist/export them or reuse them across connection generations. Do not commit real inventories, infrastructure URLs, tokens, private CA keys or signing material. See `SECURITY.md` and `docs/40-profile-tls-option.md` before changing auth/TLS behavior.

## Delivery and claims
- Follow `CONTRIBUTING.md`: small branches/PRs; API changes cite official PVE contracts and update `docs/15-verification-matrix.md`. Do not mark planned catalog entries verified: `check_premium.py` requires `planned_unimplemented`.
- `.github/workflows/checks.yml` compiles a debug APK without retaining it. Successful push checks on `main` automatically trigger `.github/workflows/release-android.yml` for that exact checked SHA; manual dispatch is main-only.
- Signed ARM64/ARMv7 prerelease APKs and checksums go directly to GitHub Releases, never Actions artifacts. Signing configuration is injected by CI; preserve external signing and never substitute debug keys or equate prerelease publication with certification.
