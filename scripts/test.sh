#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
swift test --package-path "$ANDROFEST_ROOT/shared/protocol/swift"
swift test --package-path "$ANDROFEST_ROOT/apps/macos"
"$ANDROFEST_ROOT/apps/android/gradlew" -p "$ANDROFEST_ROOT/apps/android" :core:protocol:test :app:testDebugUnitTest "$@"
