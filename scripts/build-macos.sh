#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
python3 "$TWINVIA_ROOT/scripts/build-ble-helper.py"
host_arch="$(uname -m)"
xcodebuild -project "$TWINVIA_ROOT/apps/macos/Twinvia.xcodeproj" \
    -scheme Twinvia -configuration Debug -destination "platform=macOS,arch=$host_arch" \
    -derivedDataPath "$TWINVIA_ROOT/.artifacts/xcode" CODE_SIGNING_ALLOWED=NO build "$@"
mkdir -p "$TWINVIA_ROOT/.artifacts/macos"
# Preserve locally retained resources from earlier builds, but never package them.
python3 - "$TWINVIA_ROOT" <<'PY'
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
app_resources="$TWINVIA_ROOT/.artifacts/xcode/Build/Products/Debug/Twinvia.app/Contents/Resources"
mkdir -p "$app_resources/ThirdPartyNotices"
cp "$TWINVIA_ROOT/vendor/sparkle/LICENSE" "$app_resources/ThirdPartyNotices/Sparkle.txt"
ditto "$TWINVIA_ROOT/.artifacts/bluetooth/TwinviaBluetooth.app" "$app_resources/TwinviaBluetooth.app"
python3 "$TWINVIA_ROOT/scripts/sign-macos.py" "$TWINVIA_ROOT/.artifacts/xcode/Build/Products/Debug/Twinvia.app"
ditto "$TWINVIA_ROOT/.artifacts/xcode/Build/Products/Debug/Twinvia.app" "$TWINVIA_ROOT/.artifacts/macos/Twinvia.app"
echo "App: $TWINVIA_ROOT/.artifacts/macos/Twinvia.app"
