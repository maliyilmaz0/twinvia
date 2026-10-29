#!/usr/bin/env python3
"""Sign update metadata and Sparkle archive with a private seed supplied only via the environment."""
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def sign_release(directory: Path, version: str, seed: bytes) -> None:
    if len(seed) != 32:
        raise ValueError('Expected an Ed25519 private seed')
    info = plistlib.loads((ROOT / 'apps/macos/Configuration/Info.plist').read_bytes())
    if version != info['CFBundleShortVersionString']:
        raise ValueError('Update version does not match source')
    apk = directory / f'Twinvia-{version}-android-preview.apk'
    mac = directory / f'Twinvia-{version}-macos-arm64-preview.zip'
    if not (0 < apk.stat().st_size <= 209_715_200 and 0 < mac.stat().st_size <= 536_870_912):
        raise ValueError('Release assets exceed updater limits')
    with tempfile.TemporaryDirectory(prefix='twinvia-update-sign-') as temporary:
        key = Path(temporary) / 'seed.der'
        key.write_bytes(bytes.fromhex('302e020100300506032b657004220420') + seed)
        key.chmod(0o600)
        def signature(data: bytes) -> str:
            content = Path(temporary) / 'content'
            content.write_bytes(data)
            signed = subprocess.check_output(['openssl', 'pkeyutl', '-sign', '-rawin', '-inkey', str(key), '-keyform', 'DER', '-in', str(content)])
            return base64.b64encode(signed).decode()
        # Refuse using an accidentally rotated signing key for existing updater clients.
        public = subprocess.check_output(['openssl', 'pkey', '-in', str(key), '-inform', 'DER', '-pubout', '-outform', 'DER'])[-32:]
        if base64.b64encode(public).decode() != info['SUPublicEDKey']:
            raise ValueError('Signing key does not match the app updater public key')
        base = f'https://github.com/maliyilmaz0/twinvia/releases/download/v{version}/'
        payload = json.dumps({'version': version, 'build': int(info['CFBundleVersion']), 'android': {
            'url': base + apk.name, 'sha256': hashlib.sha256(apk.read_bytes()).hexdigest(), 'size': apk.stat().st_size,
        }}, sort_keys=True, separators=(',', ':')).encode()
        (directory / 'update-manifest.json').write_bytes(payload)
        (directory / 'update-manifest.sig').write_text(signature(b'Twinvia Android Update v1\x00' + payload) + '\n')
        namespace = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
        ET.register_namespace('sparkle', namespace)
        rss = ET.Element('rss', {'version': '2.0'})
        channel = ET.SubElement(rss, 'channel')
        ET.SubElement(channel, 'title').text = 'Twinvia updates'
        item = ET.SubElement(channel, 'item')
        ET.SubElement(item, 'title').text = f'Twinvia {version}'
        ET.SubElement(item, f'{{{namespace}}}minimumSystemVersion').text = '14.0'
        ET.SubElement(item, 'enclosure', {'url': base + mac.name, 'length': str(mac.stat().st_size), 'type': 'application/octet-stream',
            f'{{{namespace}}}version': str(info['CFBundleVersion']), f'{{{namespace}}}shortVersionString': version,
            f'{{{namespace}}}edSignature': signature(mac.read_bytes())})
        ET.ElementTree(rss).write(directory / 'appcast.xml', encoding='utf-8', xml_declaration=True)
    files = sorted(p for p in directory.iterdir() if p.name != 'SHA256SUMS')
    (directory / 'SHA256SUMS').write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest() + '  ' + p.name + '\n' for p in files))


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--version', required=True)
    args = parser.parse_args()
    sign_release(args.directory, args.version, base64.b64decode(os.environ['TWINVIA_UPDATE_PRIVATE_KEY'].strip(), validate=True))
