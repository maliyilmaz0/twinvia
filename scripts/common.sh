#!/usr/bin/env bash
set -euo pipefail

TWINVIA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Compatibility for older local tooling; product scripts use TWINVIA_ROOT.
ANDROFEST_ROOT="$TWINVIA_ROOT"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
if [[ -z "${ANDROID_HOME:-}" && -d "$HOME/Library/Android/sdk" ]]; then
    export ANDROID_HOME="$HOME/Library/Android/sdk"
fi
