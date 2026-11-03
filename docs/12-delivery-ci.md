# CI/CD, Android Build and Release Engineering

## Platform rules
Keep only Android target from Flutter: `flutter create --platforms=android ... app`. Do not enable desktop/web/iOS in generated project. This does **not** prevent Dart package support for other platforms; it limits the built app target. APK/AAB is the delivery artifact. Phone UI is primary; Android tablet behavior may scale but is not designed/supported.

## Toolchain policy
- Use Flutter **stable** channel, record exact `flutter --version`, Dart SDK and Flutter engine revision in toolchain note and CI. Use a lockfile; avoid float-to-latest dependencies in reproducible release builds.
- Android minimum app API level **26** is a proposed product choice, not a Flutter minimum requirement. Validate with each selected package (recent secure storage majors require newer Android/compile SDK). For current `flutter_secure_storage` v11, inspect package changelog and set `compileSdk` >= its published minimum (reported 37 in 2026); use up-to-date Android Gradle Plugin/JDK/Flutter support matrix.
- `targetSdk`/`compileSdk` must comply with current Google Play policy **at release time**, not guessed months ahead.
- Use application ID after ownership decision (example placeholder `com.example.virthelm`); change before release; avoid Proxmox trademark insinuation.

## CI gates (after generating `app/`)
1. dependency resolution (locked), `dart format --output=none --set-exit-if-changed .`
2. `flutter analyze --fatal-infos`
3. `flutter test --coverage`
4. Android debug build: `flutter build apk --debug` for compile verification
5. security checks: detect secrets, audit dependencies, inspect Android manifest and release network config
6. optional integration tests against **mock** PVE in PR CI, and opt-in manually gated tests against disposable lab
7. code review approval before release tags; do not put PVE secrets in Actions logs/secrets without strict scoping.

## Sample GitHub Actions after app exists
Use [.github/workflows/checks.yml](../.github/workflows/checks.yml): it checks docs now and conditionally runs Flutter analysis/build when `app/pubspec.yaml` exists. Pinned production workflow should use an exact tested Flutter version, not drift with `channel: stable` indefinitely.

## Android signing
- Local debug builds are not production signed.
- Release APK/AAB must use private signing key stored outside Git and in a trusted secret store. No keystore or passwords in Actions logs, artifacts or repository.
- Prefer Play App Signing if Play distribution is selected; otherwise manage offline keystore backups and signing verification.
- Generate SBOM/dependency list and release notes; retain hashes of binaries.

## Releases
Alpha: read-only and secured connection; Beta: mutations/task tracking with full staging test matrix; v1.0 only after Definition of Done. Rollback means stop rollout/revoke compromised token and re-release safe build (Android app bundles cannot be “rolled back” as arbitrary downgrades to every device).

## Operations and maintenance
Review Proxmox PVE release notes and official API viewer each minor release; revisit Android target SDK and dependency security patches at least quarterly. Monitor issues for certificate renewal, token expiry, locale/timezone, 403 changes, task schema drift and phone OS battery policy. No production automatic host operation.
