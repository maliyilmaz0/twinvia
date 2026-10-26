#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
python3 "$ANDROFEST_ROOT/scripts/build-ble-helper.py"
host_arch="$(uname -m)"
xcodebuild -project "$ANDROFEST_ROOT/apps/macos/Androfest.xcodeproj" \
    -scheme Androfest -configuration Debug -destination "platform=macOS,arch=$host_arch" \
    -derivedDataPath "$ANDROFEST_ROOT/.artifacts/xcode" CODE_SIGNING_ALLOWED=NO build "$@"
mkdir -p "$ANDROFEST_ROOT/.artifacts/macos"
# Preserve locally retained resources from earlier builds, but never package them.
python3 - "$ANDROFEST_ROOT" <<'PY'
from pathlib import Path
import sys, shutil, time
root=Path(sys.argv[1]); archive=root/'.artifacts/legacy-native-resources'/str(time.time_ns())
for index, relative in enumerate(('.artifacts/xcode/Build/Products/Debug/Twinvia.app/Contents/Resources', '.artifacts/macos/Twinvia.app/Contents/Resources')):
    for name in ('NativePeerDiscovery.app','neighbor-advertise','nan-tcp-relay'):
        path=root/relative/name
        if path.exists():
            target=archive/str(index);target.mkdir(parents=True,exist_ok=True)
            shutil.move(str(path),str(target/name))
PY
app_resources="$ANDROFEST_ROOT/.artifacts/xcode/Build/Products/Debug/Twinvia.app/Contents/Resources"
mkdir -p "$app_resources"
ditto "$ANDROFEST_ROOT/.artifacts/bluetooth/AndrofestBluetooth.app" "$app_resources/AndrofestBluetooth.app"
python3 "$ANDROFEST_ROOT/scripts/sign-macos.py" "$ANDROFEST_ROOT/.artifacts/xcode/Build/Products/Debug/Twinvia.app"
ditto "$ANDROFEST_ROOT/.artifacts/xcode/Build/Products/Debug/Twinvia.app" "$ANDROFEST_ROOT/.artifacts/macos/Twinvia.app"
echo "App: $ANDROFEST_ROOT/.artifacts/macos/Twinvia.app"
