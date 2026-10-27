#!/usr/bin/env python3
"""Keep the app's designated requirement stable across builds when Developer ID is available."""
import os
from pathlib import Path
import re
import subprocess
import sys

app = Path(sys.argv[1]).resolve()
identity = os.environ.get('TWINVIA_SIGNING_IDENTITY') or os.environ.get('ANDROFEST_SIGNING_IDENTITY')
if not identity:
    found = subprocess.run(['security', 'find-identity', '-v', '-p', 'codesigning'], capture_output=True, text=True, check=True)
    match = re.search(r'([A-F0-9]{40}) "Developer ID Application:', found.stdout)
    identity = match.group(1) if match else '-'
# Xcode debug builds include __preview.dylib and a product debug dylib.
# Traced builds can leave these unsigned even when ordinary builds do not.
# Sign libraries inside-out; separately signed helper apps retain their identity.
for library in sorted((app / "Contents/MacOS").glob("*.dylib")):
    subprocess.run(['codesign', '--force', '--sign', identity, str(library)], check=True)
# Do not use --deep to overwrite nested helper signatures while signing.
subprocess.run(['codesign', '--force', '--sign', identity, str(app)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
print('Mac app signed with ' + ('ad-hoc identity (no Developer ID available)' if identity == '-' else 'the configured or installed signing identity'))
