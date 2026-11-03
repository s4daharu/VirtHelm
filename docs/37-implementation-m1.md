# VirtHelm implementation milestone M1 — Android app source

Status: First functional Flutter source committed as code, pending GitHub Actions compilation and real-device/PVE lab verification.

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
