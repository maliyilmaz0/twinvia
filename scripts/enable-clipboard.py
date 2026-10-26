#!/usr/bin/env python3
"""Start the clipboard-only shell helper. USB may be removed after setup.

Run again after a phone reboot. Normal pairing and device permissions are unchanged.
"""
import argparse
from pathlib import Path
import re
import subprocess
import time
import os

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--serial')
args = parser.parse_args()
sdk = Path(os.environ.get('ANDROID_HOME', Path.home() / 'Library/Android/sdk'))
adb = [str(sdk/'platform-tools/adb')] + (['-s', args.serial] if args.serial else [])

def run(*arguments, check=True, input=None):
    return subprocess.run(adb + list(arguments), capture_output=True, text=True, check=check, input=input)

subprocess.run(['python3', str(ROOT/'scripts/build-clipboard-helper.py')], check=True)
packages = run('shell', 'pm', 'list', 'packages', '-U', 'dev.androfest.android').stdout
match = re.search(r'^package:dev\.androfest\.android uid:(\d+)\s*$', packages, re.M)
if not match:
    raise SystemExit('Install the Twinvia application first')
uid = int(match.group(1))
assert uid % 100000 >= 10000
prefix = '/data/local/tmp/androfest-clipboard-' + str(uid)
run('shell', 'am', 'start', '-n', 'dev.androfest.android/.MainActivity')
for _ in range(40):
    result = run('shell', 'run-as', 'dev.androfest.android', 'cat', 'files/clipboard-helper.json', check=False)
    if result.returncode == 0 and result.stdout.strip():
        metadata = result.stdout
        break
    time.sleep(0.25)
else:
    raise SystemExit('Clipboard connection metadata is not ready; open Twinvia and retry')
import json
info = json.loads(metadata)
assert info['uid'] == uid and 1024 <= info['port'] <= 65535 and re.fullmatch('[a-f0-9]{64}', info['secret'])
# Never print or save the per-installation IPC secret on the Mac.
run('shell', 'umask 077; cat > '+prefix+'.json.tmp; chmod 600 '+prefix+'.json.tmp; mv -f '+prefix+'.json.tmp '+prefix+'.json', input=metadata)
del metadata, info
old = run('shell', 'cat', prefix+'.pid', check=False).stdout.strip()
if old.isdigit():
    command = run('shell', 'cat', '/proc/'+old+'/cmdline', check=False).stdout.split('\0')
    if 'dev.androfest.clipboard.ClipboardAgent' in command and str(uid) in command:
        run('shell', 'kill', '-TERM', old)
        time.sleep(0.3)
run('push', str(ROOT/'.artifacts/android/AndrofestClipboardHelper.jar'), prefix+'.jar')
# Only fixed paths and the validated numeric UID are interpolated into shell code.
command = ('CLASSPATH='+prefix+'.jar nohup app_process / dev.androfest.clipboard.ClipboardAgent '+str(uid)
           +' < /dev/null > '+prefix+'.log 2>&1 & echo $! > '+prefix+'.pid')
run('shell', command)
for _ in range(20):
    log = run('shell', 'cat', prefix+'.log', check=False).stdout
    if 'Twinvia clipboard helper ready' in log:
        print('Clipboard helper started. USB can be disconnected. Reactivate after phone reboot.')
        break
    time.sleep(0.25)
else:
    raise SystemExit('Clipboard helper did not start; inspect its local device log')
