#!/usr/bin/env bash
# Generate the Android-only native runner with the installed stable Flutter SDK.
# This is used by CI and a developer's first local checkout.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/app"
flutter create --platforms=android --project-name virthelm --org com.s4daharu --no-pub .
python3 "$ROOT/scripts/harden_android.py"
flutter pub get
