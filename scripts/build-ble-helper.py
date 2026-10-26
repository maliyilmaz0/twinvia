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
                '--product','TwinviaBleBridge','--jobs','6'],check=True)
app = root/'.artifacts/bluetooth/TwinviaBluetooth.app'
(app/'Contents/MacOS').mkdir(parents=True,exist_ok=True)
shutil.copy2(package/'.build/debug/TwinviaBleBridge',app/'Contents/MacOS/TwinviaBleBridge')
notices = app/'Contents/Resources/ThirdPartyNotices'
notices.mkdir(parents=True, exist_ok=True)
upstream = root/'.tooling/google-nearby'
licenses = {
    'Google-Nearby.txt': upstream/'LICENSE',
    'Ukey2.txt': upstream/'third_party/ukey2/ukey2/LICENSE',
    'Protobuf.txt': upstream/'third_party/protobuf/LICENSE',
    'UTF8-Range.txt': upstream/'third_party/protobuf/third_party/utf8_range/LICENSE',
    'Nlohmann-JSON.txt': upstream/'third_party/json/json/LICENSE.MIT',
    'Abseil.txt': package/'.build/checkouts/abseil-cpp-SwiftPM/LICENSE',
    'BoringSSL.txt': package/'.build/checkouts/boringssl-SwiftPM/LICENSE',
    'Fiat-Crypto.txt': package/'.build/checkouts/boringssl-SwiftPM/src/third_party/fiat/LICENSE',
}
for name, source in licenses.items():
    shutil.copy2(source, notices/name)
(notices/'MurmurHash3.txt').write_text(
    'MurmurHash3 was written by Austin Appleby, and is placed in the public domain.\n'
    'https://github.com/aappleby/smhasher\n')
info={'CFBundleIdentifier':'dev.androfest.bluetooth','CFBundleName':'Twinvia Bluetooth',
      'CFBundleExecutable':'TwinviaBleBridge','CFBundlePackageType':'APPL',
      'CFBundleShortVersionString':'0.9.0','CFBundleVersion':'11','LSUIElement':True,
      'NSBluetoothAlwaysUsageDescription':'Keep your paired Android phone connected over encrypted Bluetooth LE.'}
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
subprocess.run([sys.executable,str(root/'scripts/sign-macos.py'),str(app)],check=True)
print(app)
