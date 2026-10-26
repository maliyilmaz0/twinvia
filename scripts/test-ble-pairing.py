#!/usr/bin/env python3
"""Fresh QR/TLS pairing test in an unused isolated package; preserve daily trust."""
import argparse
import json
import os
import plistlib
from pathlib import Path
import re
import signal
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
DAILY_PACKAGE = 'dev.androfest.android'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial')
    parser.add_argument('--package', default=DAILY_PACKAGE + '.pairingtest')
    parser.add_argument('--apk', type=Path, default=ROOT / '.artifacts/ble-integration/Twinvia-pairingtest.apk')
    args = parser.parse_args()
    if not re.fullmatch(re.escape(DAILY_PACKAGE) + r'\.pairingtest[a-z0-9]*', args.package):
        parser.error('Use a distinct .pairingtest suffix; daily application data must remain untouched')
    sdk = Path(os.environ.get('ANDROID_HOME', Path.home() / 'Library/Android/sdk'))
    adb = [str(sdk / 'platform-tools/adb')] + (['-s', args.serial] if args.serial else [])
    app = ROOT / '.artifacts/macos/Twinvia.app'
    exe = app / 'Contents/MacOS/Twinvia'
    if not args.apk.is_file() or not exe.is_file():
        parser.error('Build the isolated APK and packaged Mac app first')

    def run(*parts, input=None):
        return subprocess.run([*adb, *parts], input=input, capture_output=True, check=True, timeout=30)

    # Every precondition runs before stopping the daily bridge or changing test state.
    packages = run('shell', 'pm', 'list', 'packages', args.package).stdout.decode().splitlines()
    if 'package:' + args.package in packages:
        parser.error('Existing test package preserved. Build/select an unused isolated test suffix.')
    badging = subprocess.check_output([str(sdk / 'build-tools/36.0.0/aapt2'), 'dump', 'badging', str(args.apk)], text=True)
    if not re.search(r"^package: name='" + re.escape(args.package) + "'", badging, re.M):
        parser.error('APK identity does not match the requested isolated package')

    directory = ROOT / '.artifacts/ble-integration' / ('first-pairing-' + uuid.uuid4().hex)
    directory.mkdir(parents=True, mode=0o700)
    report = {'transport': 'BLE + pinned TLS', 'freshQRPairing': False, 'savedReconnect': False,
              'testNotification': False, 'USB': 'test control and QR bootstrap only; no forwarding'}
    probe = None
    test_installed = False
    daily_stopped = False
    component = args.package + '/dev.androfest.android.MainActivity'

    def activity(extra=None):
        parts = ['shell', 'am', 'start', '-W', '-n', component]
        if extra:
            parts += ['--ez', 'dev.androfest.' + extra, 'true']
        run(*parts)

    def snapshot():
        return json.loads((directory / 'status.json').read_text())

    def wait(predicate, seconds=100):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if probe.poll() is not None:
                raise RuntimeError('Mac test process exited')
            try:
                if predicate():
                    return
            except (FileNotFoundError, json.JSONDecodeError):
                pass
            time.sleep(0.5)
        raise RuntimeError('BLE pairing test timed out')

    try:
        run('install', str(args.apk))
        test_installed = True
        for permission in ('BLUETOOTH_SCAN', 'BLUETOOTH_CONNECT', 'BLUETOOTH_ADVERTISE', 'NEARBY_WIFI_DEVICES'):
            run('shell', 'pm', 'grant', args.package, 'android.permission.' + permission)
        # One Mac advertiser at a time. The exact daily process closes its child
        # pipe on exit; the helper stops on EOF. Never kill unrelated apps.
        daily_app = Path('/Applications/Twinvia.app')
        daily_info = plistlib.loads((daily_app/'Contents/Info.plist').read_bytes())
        daily_binary = daily_info['CFBundleExecutable']
        if daily_binary not in {'Twinvia', 'Androfest'}:
            raise RuntimeError('Unexpected installed Twinvia executable; daily process preserved')
        daily_executable = str(daily_app/'Contents/MacOS'/daily_binary)
        processes = subprocess.check_output(['ps', '-axo', 'pid=,comm='], text=True)
        for row in processes.splitlines():
            fields = row.strip().split(None, 1)
            if len(fields) == 2 and fields[1] == daily_executable:
                os.kill(int(fields[0]), signal.SIGTERM)
                daily_stopped = True
        time.sleep(2)
        run('shell', 'am', 'force-stop', DAILY_PACKAGE)
        daily_stopped = True
        with (directory / 'probe.log').open('wb') as log:
            probe = subprocess.Popen([str(exe), '--bridge-probe-directory', str(directory)], stdout=log, stderr=log)
            wait(lambda: (directory / 'invitation.txt').exists(), 20)
            link = (directory / 'invitation.txt').read_bytes()
            run('shell', 'run-as', args.package, 'mkdir', '-p', 'files')
            # Package identity is validated above; the filename and shell command are fixed.
            run('shell', 'run-as ' + args.package + " sh -c 'cat > files/debug-pairing-invitation.txt'", input=link)
            del link
            activity('DEBUG_PAIR_FROM_FILE')
            wait(lambda: snapshot()['connected'])
            report['freshQRPairing'] = True
            print('PASS fresh BLE QR pairing and pinned TLS', flush=True)
            activity('DEBUG_TEST_CONNECTION')
            wait(lambda: snapshot()['testConfirmed'], 25)
            report['testNotification'] = True
            print('PASS synthetic notification over BLE', flush=True)
            run('shell', 'am', 'force-stop', args.package)
            wait(lambda: not snapshot()['connected'], 35)
            activity()
            wait(lambda: snapshot()['connected'])
            report['savedReconnect'] = True
            print('PASS saved BLE pairing reconnects after Android restart', flush=True)
    finally:
        if test_installed:
            subprocess.run([*adb, 'shell', 'am', 'force-stop', args.package], capture_output=True, timeout=15)
        if probe is not None:
            (directory / 'STOP').touch()
            try:
                probe.wait(timeout=5)
            except subprocess.TimeoutExpired:
                probe.terminate()
                probe.wait(timeout=5)
        (directory / 'invitation.txt').unlink(missing_ok=True)
        (directory / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
        (ROOT / '.artifacts/ble-integration/first-pairing-result.json').write_text(json.dumps(report, indent=2) + '\n')
        if daily_stopped:
            subprocess.run([*adb, 'shell', 'am', 'start', '-n', DAILY_PACKAGE + '/.MainActivity'], capture_output=True, timeout=15)
            subprocess.run(['/usr/bin/open', '/Applications/Twinvia.app'], check=True)
    print(json.dumps(report), flush=True)


if __name__ == '__main__':
    main()
