# CI/CD, Android Build and Release Engineering

## Current pinned baseline
VirtHelm is Android-phone only. CI pins Flutter **3.44.4**, commits `app/pubspec.lock`, and generates the Android runner from the pinned SDK with `scripts/bootstrap_android.sh`. The generator hardens the main manifest/Gradle configuration: release Internet permission present, cleartext and app backup disabled, minSdk 26, application ID `com.s4daharu.virthelm`, and no debug-key release signing.

The generated `app/android/` directory is intentionally not committed yet; `scripts/check_android_generated.py` fails CI if the pinned Flutter template drifts away from the expected security configuration.

## CI gates
For every push and pull request:
1. documentation/premium/source consistency checks;
2. exact locked dependency resolution using `flutter pub get --enforce-lockfile` after Android generation;
3. generated Android hardening assertions;
4. `dart format --output=none --set-exit-if-changed lib test`;
5. `flutter analyze --fatal-infos`;
6. `flutter test --coverage`;
7. `flutter build apk --debug`;
8. upload of the debug APK as a compile/test artifact.

A debug APK is not a release artifact. Live PVE tests are deliberately not run automatically against production infrastructure.

## Android release requirements
Release APK/AAB signing keys and passwords must remain outside Git and Actions logs. Release signing must be configured through a reviewed external secret/signing workflow before distribution. Verify the merged release manifest, network security, target/compile SDK policy, dependency advisories, SBOM/license inventory, and binary hashes before any release tag.

## Remaining release gates
CI cannot prove server compatibility or device security. Before alpha/beta promotion, execute the PVE 9.2/8.4 lab matrix, physical Android API/device tests, TLS failure tests, backup/restore behavior, accessibility/font-scale checks, performance/load tests, secret/log scanning, and signing verification described in the test strategy and Definition of Done.
