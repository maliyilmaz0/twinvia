#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
python3 "$TWINVIA_ROOT/scripts/check-publication.py"
python3 -m unittest discover -s "$TWINVIA_ROOT/scripts/tests" -v
python3 "$TWINVIA_ROOT/scripts/format-code.py" --check "$@"
