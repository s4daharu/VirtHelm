# Developer Setup Handbook — Android-only Flutter

## Prerequisites
Flutter stable SDK + Dart from Flutter, Android Studio/SDK (current supported build tools), compatible JDK/Gradle, an Android phone or emulator, Git. Follow https://docs.flutter.dev/platform-integration/android/setup and run `flutter doctor -v`. Flutter itself is **not installed in the authoring environment**, so no APK build or dependency lock was verified in this package.

## Create app in this repository
```bash
flutter --version
flutter doctor -v
flutter create --platforms=android --org com.example --project-name virthelm app
cd app
flutter pub add dio flutter_riverpod go_router flutter_secure_storage shared_preferences
flutter pub add --dev flutter_lints mocktail
flutter pub get
flutter analyze
flutter test
flutter run
```
Replace `com.example` with a namespace you own before releasing. This command creates `app/android` but no iOS/web/desktop runners. Use `flutter pub add --dev` syntax supported by installed Flutter; review selected package releases and update `pubspec.lock` only under code review. Configure `app/android/app/build.gradle.kts` (or generated Gradle variant) with chosen `minSdk=26` (product decision), `compileSdk` that meets dependencies (e.g., secure storage 11 needs 37 according to its release notes) and appropriate `targetSdk` when publishing. Re-run Gradle compatibility checks; do not hardcode a guessed AGP or Kotlin plugin version.

## Android manifest hardening
- Ensure `INTERNET` permission (Flutter typically generates/needs it for networked release use; verify merged release manifest).
- Set release cleartext disabled: `android:usesCleartextTraffic="false"` or carefully reviewed `networkSecurityConfig`.
- Disable Android app auto-backup (`android:allowBackup="false"`) **or** exclude secure-storage preferences from data extraction/backup rules. Test restore behavior on physical device; don't assume manifest alone secures every API-level backup path.
- Do not request storage/all-files or privileged permissions.
- Debug network security overrides, if any, must not apply to release builds.

## PVE staging prerequisites
1. Obtain PVE 9.2 or 8.4 disposable environment; keep management network behind private LAN/VPN.
2. Set up a trusted HTTPS certificate chain and valid DNS hostname; test on Android phone.
3. Create read-only and power-operation test accounts with **separated** tokens restricted to disposable guest IDs; store token secret only in local secure config, never git.
4. Make one disposable QEMU VM and LXC; capture pre-state/snapshot for rollback.
5. Run `examples/README.md` GET smoke checks with shell environment variables. Do **not** use `curl -k` or paste real secrets into terminal history/scripts.
6. Record version/ACL, API endpoint method/parameter schema and sanitized fixture IDs in verification matrix.

## GitHub repository

VirtHelm is hosted in the private repository `s4daharu/VirtHelm`. You need collaborator access to clone or contribute:

```bash
git clone https://github.com/s4daharu/VirtHelm.git
cd VirtHelm
python3 scripts/check_docs.py
```

Work in feature branches and submit pull requests after checks. Avoid uploading any PVE server, token, or task-sensitive data.

## Local commands
```bash
python3 scripts/check_docs.py
cd app && dart format --output=none --set-exit-if-changed . && flutter analyze && flutter test
cd app && flutter build apk --debug
```

## Troubleshooting
- Wrong cert: fix name/CA and VPN; never disable TLS validation.
- `401`: token may be malformed/expired/revoked. Header uses one `=` before secret.
- `403`: backing user ACL or separated-token ACL lacks endpoint privilege. Inspect permission path in viewer.
- Timeouts: firewall, VPN routing, port 8006, node health and DNS.
- `api2` response unexpected: save sanitized fixture, compare with version-specific viewer, do not silently cast.
- Secure-storage errors after device restore: review app backup policy and provider migration notes.
