#!/usr/bin/env bash
# Smart device health: single-command static, unit and release APK QA.
# Use --ios on macOS to also compile the iOS release runner (without signing).
set -euo pipefail

cd "$(dirname "$0")/.."

echo "== smart device health QA =="
echo "Commit: $(git rev-parse --short HEAD)"
echo "== Android release startup regression guard =="
grep -Fq '"proguard-rules.pro"' android/app/build.gradle.kts
grep -Fq 'androidx.work.impl.WorkDatabase_Impl' android/app/proguard-rules.pro
grep -Fq 'androidx.work.impl.WorkDatabase' android/app/proguard-rules.pro
flutter --version
flutter pub get
# Legacy advertising files contain informational lint notices; error/warning
# diagnostics must still fail the command.
flutter analyze --no-fatal-infos
flutter test
flutter build apk --release

if [[ "${1:-}" == "--ios" ]]; then
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "iOS compilation requires macOS" >&2
    exit 1
  fi
  flutter build ios --release --no-codesign
fi

echo "Build and unit QA passed. Real-device foreground and release runtime QA still required."
echo "APK: build/app/outputs/flutter-apk/app-release.apk"
