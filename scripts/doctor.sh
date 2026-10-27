#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
missing=0
if xcodebuild -version; then :; else missing=1; fi
if swift --version; then :; else missing=1; fi
if java -version; then :; else missing=1; fi
if [[ -n "${ANDROID_HOME:-}" && -f "$ANDROID_HOME/platforms/android-37.0/android.jar" ]]; then
    echo "Android SDK 37.0: $ANDROID_HOME"
    if [[ -x "$ANDROID_HOME/platform-tools/adb" ]]; then "$ANDROID_HOME/platform-tools/adb" devices; fi
else
    echo "Android SDK 37.0 is required. Install API 37.0 using Android Studio SDK Manager."
    missing=1
fi
exit "$missing"
