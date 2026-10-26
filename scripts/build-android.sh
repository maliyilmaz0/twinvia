#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
python3 "$ANDROFEST_ROOT/scripts/build-clipboard-helper.py"
"$ANDROFEST_ROOT/apps/android/gradlew" -p "$ANDROFEST_ROOT/apps/android" :core:protocol:test :app:testDebugUnitTest :app:lintDebug :app:assembleDebug "$@"
mkdir -p "$ANDROFEST_ROOT/.artifacts/android"
cp "$ANDROFEST_ROOT/apps/android/app/build/outputs/apk/debug/app-debug.apk" "$ANDROFEST_ROOT/.artifacts/android/Twinvia-debug.apk"
echo "APK: $ANDROFEST_ROOT/.artifacts/android/Twinvia-debug.apk"
