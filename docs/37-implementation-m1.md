# VirtHelm implementation milestone M1 — Android app source

Status: First Flutter Android debug APK now builds in GitHub Actions. Real-device/PVE lab and release/security verification remain open.

## Scope
Flutter 3.47 stable-compatible Dart source, Android phone-only generator, Material 3 views, profile onboarding and secure API token storage, direct PVE HTTP reader, VM/LXC discovery, guarded guest actions and UPID tracker. Read `app/README.md` for setup and limitations.

## Chosen deviations
- Uses Flutter ChangeNotifier + native Navigator for this first vertical slice to limit dependency risk. Premium architecture documentation recommends evaluating Riverpod/go_router in a subsequent refactor; do not claim they have been implemented.
- Android runner is intentionally generated with the developer's installed Flutter SDK via `scripts/bootstrap_android.sh`, since no Flutter/Android SDK is available in this authoring runtime. It is required before building and is not pre-committed. The CI does generate one before tests and APK build.
- `flutter_secure_storage` 10.3.x used instead of major 11 because its Android compile/min SDK requirements need explicit CI validation and v11 upgrade design.

## Security and correctness gates still open
- Lab PVE 8.4/9.2 API and ACL tests; certificate acceptance on Android physical devices.
- Device loss/restored device secure-storage migration, backup exclusion and token deletion verification.
- Verify QEMU/LXC power endpoint semantics and no duplicate mutation under network fault injection.
- Task tracker is foreground/in-memory only. Stale status always disables controls. No persistent offline mutation queue.
- Android build, test, Play signing, accessibility and performance evidence. Repository CI should report an honest PASS/FAIL of source build.

## Acceptance check
From root `bash scripts/bootstrap_android.sh`, then `cd app && flutter analyze && flutter test && flutter build apk --debug` on machine with Android SDK. CI runs the same. Never claim a debug build as production-ready or 100% correct without full server/device validation.

## Initial Android CI diagnosis (2026-11-04)
First Flutter build run used 3.47.9. Dart analysis and unit/widget tests passed, but Android debug compilation failed resolving Kotlin 2.3.0/AGP 9 Gradle artifacts and the old Android DSL. Pin Flutter 3.44.4 while investigating current Kotlin/AGP compatibility. Capture the next CI run before declaring an APK deliverable. References: https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin and https://github.com/flutter/flutter/blob/master/CHANGELOG.md.

## Verified debug CI build (2026-11-04)
The pinned Flutter 3.44.4 run [41712997783](https://github.com/s4daharu/VirtHelm/actions/runs/41712997783) passed source checks, `flutter analyze --fatal-infos`, Flutter tests and `flutter build apk --debug`. It uploaded the **debug** APK artifact. This resolves the initial compilation blocker only, not signing, real-device, PVE compatibility, or distribution readiness.

## M1 safe-operation follow-up (feature branch)
- A per-guest, per-active-profile single-flight lock spans live status preflight, exactly one POST, and UPID task completion. A second action is rejected while a task runs.
- Before each POST, ensure the guest is the exact current inventory snapshot object, unambiguously located, and its node, VMID, type and state still match. Inventory replacement or profile activation during preflight blocks the old action.
- Ambiguous write outcomes remain locked for the current connection session. The operator must inspect server task history and actual guest state before intentionally reconnecting to re-enable actions. There is **no** automatic retry or claim of success based on HTTP submission alone.
- The guest UI disables power actions for locked targets. Deleting the active profile invalidates its in-memory session **before** awaiting vault I/O, so deletion cannot race a preflight into a new POST. Controller regression tests cover concurrent actions, unknown outcomes, stale records, profile switching, deletion, and terminal UPID release.
- The feature branch needs its own GitHub Actions check and lab tests before merge/release. These guards reduce risk but do not eliminate a server-side race between status GET and POST.
