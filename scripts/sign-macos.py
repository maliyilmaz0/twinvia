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
# Xcode may strip parts of a binary framework signature while embedding it.
# Re-sign its Mach-O executables and nested services from the inside out.
frameworks = app / "Contents/Frameworks"
if frameworks.exists():
    targets = []
    for entry in frameworks.rglob('*'):
        if entry.is_symlink():
            continue
        if entry.is_file():
            with entry.open('rb') as stream:
                magic = stream.read(4)
            if magic in (b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'):
                targets.append(entry)
        elif entry.suffix in {'.app', '.xpc', '.framework'}:
            targets.append(entry)
    for target in sorted(targets, key=lambda p: len(p.parts), reverse=True):
        subprocess.run(['codesign', '--force', '--sign', identity, '--preserve-metadata=entitlements', str(target)], check=True)
# Do not use --deep to overwrite nested helper signatures while signing.
subprocess.run(['codesign', '--force', '--sign', identity, str(app)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
print('Mac app signed with ' + ('ad-hoc identity (no Developer ID available)' if identity == '-' else 'the configured or installed signing identity'))
