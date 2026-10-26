#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
adb_bin="${ANDROID_HOME:?Set ANDROID_HOME to the Android SDK directory}/platform-tools/adb"
apk="$ANDROFEST_ROOT/.artifacts/android/Twinvia-debug.apk"
if [[ ! -f "$apk" ]]; then "$ANDROFEST_ROOT/scripts/build-android.sh"; fi
serial=""
clipboard=0
for argument in "$@"; do
    if [[ "$argument" == --clipboard ]]; then clipboard=1
    elif [[ "$argument" == --* || -n "$serial" ]]; then
        echo 'Usage: install-android.sh [DEVICE_SERIAL] [--clipboard]' >&2; exit 2
    else serial="$argument"
    fi
done
if [[ -n "$serial" ]]; then
    "$adb_bin" -s "$serial" install -r "$apk"
else
    "$adb_bin" install -r "$apk"
fi
# Shell clipboard access is deliberately opt-in, not a side effect of APK installation.
if [[ "$clipboard" == 1 ]]; then
    if [[ -n "$serial" ]]; then
        python3 "$ANDROFEST_ROOT/scripts/enable-clipboard.py" --serial "$serial"
    else
        python3 "$ANDROFEST_ROOT/scripts/enable-clipboard.py"
    fi
fi
