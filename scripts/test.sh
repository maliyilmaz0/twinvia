#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
swift test --package-path "$TWINVIA_ROOT/shared/protocol/swift"
swift test --package-path "$TWINVIA_ROOT/apps/macos"
"$TWINVIA_ROOT/apps/android/gradlew" -p "$TWINVIA_ROOT/apps/android" :core:protocol:test :app:testDebugUnitTest "$@"
