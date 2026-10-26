#!/usr/bin/env python3
"""Keep the app's designated requirement stable across builds when Developer ID is available."""
import os
from pathlib import Path
import re
import subprocess
import sys

app = Path(sys.argv[1]).resolve()
identity = os.environ.get('ANDROFEST_SIGNING_IDENTITY')
if not identity:
    found = subprocess.run(['security', 'find-identity', '-v', '-p', 'codesigning'], capture_output=True, text=True, check=True)
    match = re.search(r'([A-F0-9]{40}) "Developer ID Application:', found.stdout)
    identity = match.group(1) if match else '-'
# Sign nested product helpers first; do not replace their signatures with --deep.
subprocess.run(['codesign', '--force', '--sign', identity, str(app)], check=True)
subprocess.run(['codesign', '--verify', '--strict', str(app)], check=True)
print('Mac app signed with ' + ('ad-hoc identity (no Developer ID available)' if identity == '-' else 'the configured or installed signing identity'))
