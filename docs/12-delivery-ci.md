# CI/CD, Android Build and Release Engineering

## Current pinned baseline
VirtHelm is Android-phone only. CI pins Flutter **3.44.4**, commits `app/pubspec.lock`, and generates the Android runner from the pinned SDK with `scripts/bootstrap_android.sh`. The generator hardens the main manifest/Gradle configuration: release Internet permission present, cleartext and app backup disabled, minSdk 26, application ID `com.s4daharu.virthelm`, and no debug-key release signing.

The generated `app/android/` directory is intentionally not committed yet; `scripts/check_android_generated.py` fails CI if the pinned Flutter template drifts away from the expected security configuration.

## CI gates
`checks.yml` runs the documentation/premium/source and Python regression checks
on pushes to `main` and on pull requests. `android-ci.yml` runs on Android-impacting PRs
and pushes to `main` (or manual dispatch) and adds:
1. the same repository checks;
2. exact locked dependency resolution using `flutter pub get --enforce-lockfile` after Android generation;
3. generated Android hardening assertions;
4. `dart format lib test` with a clean diff required;
5. `flutter analyze --no-pub --fatal-infos`;
6. `flutter test --no-pub`;
7. `flutter build apk --debug --target-platform android-arm64 --no-pub`;
8. no APK upload or retention in Actions artifact storage; the debug build is a compile-only gate.

A debug APK is not a release artifact. Live PVE tests are deliberately not run automatically against production infrastructure.

## Direct APK release assets
`release-android.yml` runs after a successful Android CI push to `main` and
checks out the exact checked SHA. It also supports manual dispatch on `main`,
with repository and Flutter checks. The workflow verifies the signing
certificate and the exact native ABI in each split before uploading signed
ARM64/ARMv7 APKs and checksums directly using `gh release create` and
`gh release upload`. All three uploaded assets must match the expected sizes
before it emits links. Reruns use an attempt-specific tag rather than
force-moving an existing tag.

Downloads are public on the repository's Releases page. There is no Actions
artifact handoff; existing artifacts expire or may be removed manually. SDK/Pub
cache storage is separate. Android CI saves only the Gradle dependency and
wrapper distribution directories to its Gradle cache; the signing workflow is
restore-only and does not cache task outputs or signing files.

## Android release requirements
Release APK/AAB signing keys and passwords must remain outside Git and Actions logs. Release signing must be configured through a reviewed external secret/signing workflow before distribution. Verify the merged release manifest, network security, target/compile SDK policy, dependency advisories, SBOM/license inventory, and binary hashes before any release tag.

## Remaining release gates
CI cannot prove server compatibility or device security. Before alpha/beta promotion, execute the PVE 9.2/8.4 lab matrix, physical Android API/device tests, TLS failure tests, backup/restore behavior, accessibility/font-scale checks, performance/load tests, secret/log scanning, and signing verification described in the test strategy and Definition of Done.
