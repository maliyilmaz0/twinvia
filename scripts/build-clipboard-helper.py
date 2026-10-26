#!/usr/bin/env python3
"""Build the original, clipboard-only Android shell helper; changes no permissions."""
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
sdk = Path(os.environ.get('ANDROID_HOME', Path.home() / 'Library/Android/sdk'))
java = Path(os.environ.get('JAVA_HOME', '/Library/Java/JavaVirtualMachines/jdk-21.jdk/Contents/Home'))
work = ROOT / '.tooling/clipboard/classes'
work.mkdir(parents=True, exist_ok=True)
for old in work.rglob('*.class'):
    old.unlink()
platform = sdk / 'platforms/android-36/android.jar'
source = ROOT / 'tools/clipboard-helper/src/dev/androfest/clipboard/ClipboardAgent.java'
subprocess.run([str(java/'bin/javac'), '--release', '17', '-cp', str(platform), '-d', str(work), str(source)], check=True)
output = ROOT / '.artifacts/android/AndrofestClipboardHelper.jar'
output.parent.mkdir(parents=True, exist_ok=True)
subprocess.run([str(sdk/'build-tools/36.0.0/d8'), '--lib', str(platform), '--min-api', '33', '--output', str(output),
                *map(str, work.rglob('*.class'))], env={**os.environ, 'JAVA_HOME': str(java)}, check=True)
print(output)
