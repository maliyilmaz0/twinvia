#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
python3 "$ANDROFEST_ROOT/scripts/check-publication.py"
python3 -m unittest discover -s "$ANDROFEST_ROOT/scripts/tests" -v
python3 "$ANDROFEST_ROOT/scripts/format-code.py" --check "$@"
