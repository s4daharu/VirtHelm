# Developer Setup Handbook — Android-only Flutter

## Prerequisites
Use Flutter **3.44.4** (see `app/.flutter-version`), its bundled Dart SDK, Android Studio/SDK, a compatible JDK, and Git. Run `flutter doctor -v` before building.

## Checkout and bootstrap
```bash
git clone https://github.com/s4daharu/VirtHelm.git
cd VirtHelm
python3 scripts/check_docs.py
python3 scripts/check_premium.py
python3 scripts/check_source.py
bash scripts/bootstrap_android.sh
cd app
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test --coverage
flutter build apk --debug
```

Do not rerun `flutter pub add` for the checked-in dependencies during ordinary setup. `app/pubspec.lock` is committed for reproducibility. The bootstrap script preserves that repository lockfile across `flutter create --no-pub` and resolves it with `--enforce-lockfile`.

## Generated Android runner
The runner is Android-only and uses application ID `com.s4daharu.virthelm`. The hardening script adds release Internet permission, sets `android:allowBackup="false"`, sets `android:usesCleartextTraffic="false"`, pins minSdk 26, and removes Flutter template debug-key signing from the release build. `scripts/check_android_generated.py` verifies these conditions after generation.

Release signing is intentionally absent from source control. Configure signing externally only for a reviewed release workflow. Do not weaken TLS or add a broad network-security trust exception to make a lab server connect.


## Signed split-ABI Android prerelease
The manual `.github/workflows/release-android.yml` workflow builds signed release-mode APKs only for the two supported ARM packages requested for direct distribution:

- `arm64-v8a` for 64-bit ARM Android devices.
- `armeabi-v7a` for older 32-bit ARM Android devices.

The workflow deliberately does not publish an x86/x86_64 APK. It requires the GitHub Actions secrets `RELEASE_KEYSTORE_BASE64`, `RELEASE_STORE_PASSWORD`, `RELEASE_KEY_ALIAS`, and `RELEASE_KEY_PASSWORD`; it fails closed if any are absent and never falls back to a generated or debug signing key. It verifies both APK signatures and ABI contents, emits `SHA256SUMS.txt`, uploads the files as a workflow artifact, and creates a GitHub **prerelease**.

A successful split-APK workflow proves packaging/signing mechanics only. It does not close the real-PVE, physical-device, accessibility/performance, dependency/security-review, or production release-certification gates in `docs/33-test-acceptance-release-gates.md`.

## PVE staging prerequisites
Use disposable PVE 9.2 and 8.4 environments behind LAN/VPN, trusted HTTPS names/certificates, separated least-privilege test tokens, and disposable QEMU/LXC guests. Capture sanitized endpoint/ACL/version evidence without secrets. Mutating lab tests require explicit rollback/pre-state preparation.

## Troubleshooting
- TLS error: repair hostname/CA/expiry; never disable certificate verification.
- `401`: token malformed, expired, or revoked.
- `403`: user/token ACL is insufficient for that endpoint/resource.
- Timeout/offline: verify DNS, VPN/routing, firewall, port 8006, and node health.
- Lockfile mismatch: update dependencies intentionally under review with pinned Flutter, regenerate `pubspec.lock`, and rerun the full CI gate.
- Secure-storage restore issue: keep the app fail closed and execute the physical-device backup/restore test before release.
