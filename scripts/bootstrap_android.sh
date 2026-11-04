#!/usr/bin/env bash
# Generate the Android-only native runner with the installed stable Flutter SDK.
# This is used by CI and a developer's first local checkout.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/app"
LOCK_COPY=""
restore_lock() {
  if [[ -n "$LOCK_COPY" && -f "$LOCK_COPY" ]]; then
    cp "$LOCK_COPY" pubspec.lock
    rm -f "$LOCK_COPY"
    LOCK_COPY=""
  fi
}
trap restore_lock EXIT
if [[ -f pubspec.lock ]]; then
  LOCK_COPY="$(mktemp)"
  cp pubspec.lock "$LOCK_COPY"
fi
flutter create --platforms=android --project-name virthelm --org com.s4daharu --no-pub .
python3 "$ROOT/scripts/harden_android.py"
if [[ -n "$LOCK_COPY" ]]; then
  restore_lock
  flutter pub get --enforce-lockfile
else
  rm -f pubspec.lock
  flutter pub get
fi
