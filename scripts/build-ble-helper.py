#!/usr/bin/env python3
"""Build the ordinary-permission BLE transport helper; no restricted entitlements."""
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
subprocess.run([sys.executable,str(root/'scripts/prepare-nearby-sdk.py')],check=True)
package = root/'apps/macos/BluetoothBridge'
subprocess.run(['xcrun', 'swift', 'build','--package-path',str(package),
                '--product','AndrofestBleBridge','--jobs','6'],check=True)
app = root/'.artifacts/bluetooth/AndrofestBluetooth.app'
(app/'Contents/MacOS').mkdir(parents=True,exist_ok=True)
shutil.copy2(package/'.build/debug/AndrofestBleBridge',app/'Contents/MacOS/AndrofestBleBridge')
info={'CFBundleIdentifier':'dev.androfest.bluetooth','CFBundleName':'Twinvia Bluetooth',
      'CFBundleExecutable':'AndrofestBleBridge','CFBundlePackageType':'APPL',
      'CFBundleShortVersionString':'0.9.0','CFBundleVersion':'11','LSUIElement':True,
      'NSBluetoothAlwaysUsageDescription':'Keep your paired Android phone connected over encrypted Bluetooth LE.'}
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
subprocess.run([sys.executable,str(root/'scripts/sign-macos.py'),str(app)],check=True)
print(app)
