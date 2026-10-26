#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
python3 "$TWINVIA_ROOT/scripts/build-clipboard-helper.py"
"$TWINVIA_ROOT/apps/android/gradlew" -p "$TWINVIA_ROOT/apps/android" :core:protocol:test :app:testDebugUnitTest :app:lintDebug :app:assembleDebug "$@"
mkdir -p "$TWINVIA_ROOT/.artifacts/android"
cp "$TWINVIA_ROOT/apps/android/app/build/outputs/apk/debug/app-debug.apk" "$TWINVIA_ROOT/.artifacts/android/Twinvia-debug.apk"
echo "APK: $TWINVIA_ROOT/.artifacts/android/Twinvia-debug.apk"
