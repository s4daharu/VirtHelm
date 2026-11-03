# VirtHelm Android app (M1 preview)

This folder contains the first executable Flutter/Dart implementation, **not** all planned premium features.
It targets Android **phones only**. No iOS, web, or desktop runner is generated.

## First-time developer setup

1. Install a stable Flutter SDK and Android SDK. Check `flutter doctor -v`.
2. From the **repository root**, run `bash scripts/bootstrap_android.sh`.
3. Run `cd app && flutter analyze && flutter test && flutter run`.
4. Build a debug APK with `flutter build apk --debug` (or use GitHub Actions).

The bootstrap script generates the Android native runner for your installed Flutter version and applies security-hardening attributes to the main manifest. Check in the generated `android/` runner only after confirming the exact SDK and Gradle compatibility on a developer workstation. Generated files are not yet in the repository because the authoring environment did not have Flutter/Android SDKs. **Never publish an APK without checking the native manifest and signing configuration.**

## This build actually implements

- Named profile onboarding, HTTPS host/port validation, real API-token credential verification (`/version` and `/cluster/resources`).
- Token stored with Android secure-storage plugin; only profile alias and URL in ordinary shared preferences.
- Multiple profiles with explicit switch, delete and credential erasure; per-profile Dio instance, no redirects.
- Cluster resource dashboard showing nodes and QEMU/LXC inventory; searchable guest list with last refresh timestamp.
- Guest details showing server-reported CPU and memory usage; start/shutdown/reboot/force-stop confirmation.
- Fresh guest-state preflight and inventory identity check before mutation; **exactly one POST**; a per-guest lock prevents duplicate commands while preflight/submission/task tracking is active. Ambiguous outcomes block further commands until the operator verifies server state and reconnects. Asynchronous UPID task monitoring determines final result.
- Foreground-only task polling, last-known stale UI, safe error and permission-denied messages.
- Unit and widget tests; CI Flutter analyze/test/debug APK generation.

## Not yet included

No production-validated APK or real Proxmox lab evidence; no root CA enrollment UI (Android system trust only), no user ticket/MFA, no interactive console, no persistent task history, no graphs/alerts, no restoring/snapshotting/migrating/provisioning, no PBS/PDM, no Android widgets, no subscriptions or payments. Refer to `docs/21-*` through `docs/36-*` for future milestones.

## Authentication and networking

Use a dedicated, least-privilege Proxmox VE API token, for example `operator@pve!virthelm` with its separate secret. Proxmox permissions are authoritative. Server certificate hostname and chain must validate in Android. Use a VPN rather than forwarding TCP/8006 to the public Internet. Self-signed certificates must be installed/trusted at the Android OS level or replaced with CA-issued certificates—there is no unsafe bypass. API-token access does not grant console privileges.

## Source references

- https://github.com/proxmox/pve-docs/blob/master/pveum.adoc
- https://pve.proxmox.com/pve-docs/api-viewer/
- https://docs.flutter.dev/platform-integration/android/setup

### Pinned CI toolchain
The CI workflow uses Flutter **3.44.4** with an Android-only generated runner, as a temporary pinned compatibility baseline. A first run against Flutter 3.47.9 passed Dart analysis and tests but failed in Gradle/Kotlin 2.3.0/AGP 9 artifact resolution before producing an APK. CI run [41712997783](https://github.com/s4daharu/VirtHelm/actions/runs/41712997783) passed Dart analysis, tests, and Android debug build. CI uploads a **debug-only, unsigned-for-distribution** APK artifact. This is not production or device/PVE validation.
