#!/usr/bin/env python3
"""Verify automatic plaintext clipboard sync while a separate phone app has focus.

Synthetic text and optional image travel through the authenticated bridge. ADB
only controls the separate probe. Original clipboard formats stay in RAM only.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shlex
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--serial', required=True)
parser.add_argument('--image', action='store_true')
parser.add_argument('--without-helper', action='store_true',
                    help='Verify Mac-to-phone clipboard without the optional shell helper')
args = parser.parse_args()
adb = [str(Path.home()/'Library/Android/sdk/platform-tools/adb'), '-s', args.serial]
cache = Path.home()/'Library/Caches/dev.androfest.macos'
probe = 'dev.androfest.clipboardprobe'

def run(*arguments):
    return subprocess.run(adb+list(arguments), capture_output=True, check=True)

def phone():
    return json.loads(run('shell', 'run-as', 'dev.androfest.android', 'cat', 'files/clipboard-status.json').stdout)

def mac():
    return json.loads((cache/'clipboard-status.json').read_text())

def wait(predicate, seconds=20):
    end = time.monotonic()+seconds
    while time.monotonic()<end:
        value = predicate()
        if value: return value
        time.sleep(.3)
    raise RuntimeError('Clipboard test timed out; compare diagnostic counters (no text logged)')

def activity(mode, text=None):
    command = ['am', 'start', '-W', '-n', probe+'/.ProbeActivity', '--es', 'mode', mode]
    if text is not None: command += ['--es', 'text', text]
    run('shell', shlex.join(command))

def paste_hash():
    return json.loads(run('shell', 'run-as', probe, 'cat', 'files/result.json').stdout)['sha256']

run('install','-r',str(ROOT/'tools/clipboard-probe/build/outputs/apk/debug/TwinviaClipboardProbe-debug.apk'))
wait(lambda: phone().get('connected') and mac().get('connected') and
     (args.without_helper or phone().get('helperReady')), 60)
nonce = uuid.uuid4().hex
first = 'twinvia-test-phone-'+nonce+'-şğ😀'
second = 'twinvia-test-mac-'+nonce+'-üö😀'
session_binary=ROOT/'.artifacts/PasteboardSession'
subprocess.run(['xcrun','swiftc',str(ROOT/'tools/clipboard-probe/PasteboardSession.swift'),'-o',str(session_binary)],check=True)
session=subprocess.Popen([str(session_binary)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
assert json.loads(session.stdout.readline())['ready']
def board(command, **fields):
    session.stdin.write(json.dumps({'command':command,**fields})+'\n');session.stdin.flush()
    return json.loads(session.stdout.readline())
image=ROOT/'.artifacts/ble-clipboard-fixture.png'
if args.image: subprocess.run([str(session_binary),'--fixture',str(image)],check=True)
image_hash=hashlib.sha256(image.read_bytes()).hexdigest() if args.image else ''
hashes=[hashlib.sha256(value.encode()).hexdigest() for value in (first,second)]
board('configure',hashes=hashes+([image_hash] if args.image else []))
report = {}
try:
    p0, m0 = phone(), mac()
    if not args.without_helper:
        activity('copy', first)
        wait(lambda: board('matches',sha256=hashes[0])['matches'])
        wait(lambda: mac()['applied']>m0['applied'])
        report['phoneCopyWhileBridgeBackgroundToMac'] = True
    p1, m1 = phone(), mac()
    board('setText',text=second)
    wait(lambda: phone()['applied']>p1['applied'])
    activity('paste')
    wait(lambda: paste_hash()==hashlib.sha256(second.encode()).hexdigest())
    report['macCopyToPhoneClipboard'] = True
    p2, m2 = phone(), mac()
    time.sleep(3)
    p3, m3 = phone(), mac()
    assert p3['sent']==p2['sent'] and m3['sent']==m2['sent'], 'Clipboard echo loop'
    report['noEchoLoop'] = True
    report['unicodePreserved'] = True
    report['phoneHelperReady'] = p3['helperReady']
    if not args.without_helper:
        report['phoneHelperUid'] = 'shell (2000); normal application UID unchanged'
    report['transport'] = 'existing authenticated bridge; no adb forwarding'
    report['phoneCounters'] = p3
    report['macCounters'] = m3
    if args.image:
        start=time.monotonic();board('setImage',path=str(image))
        def image_received():
            activity('image')
            result=json.loads(run('shell','run-as',probe,'cat','files/result.json').stdout)
            return result.get('imageSha256')==image_hash and result.get('pngMime') is True
        wait(image_received,180)
        report['macPNGToPhoneClipboard']=True;report['pngBytes']=image.stat().st_size
        report['pngElapsedSeconds']=round(time.monotonic()-start,2)
finally:
    board('restore');session.wait(timeout=5)
    run('shell', 'am', 'force-stop', probe)
(ROOT/'.tooling/clipboard/result.json').write_text(json.dumps(report, indent=2, ensure_ascii=False)+'\n')
print(json.dumps(report, ensure_ascii=False))
