"""Use real Ed25519/OpenSSL operations to verify update publication signatures."""
import base64
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('sign_updates', ROOT / 'scripts/sign-update-release.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class UpdateSigningTests(unittest.TestCase):
    def test_signatures_verify_and_wrong_identity_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            private = root / 'test.der'
            subprocess.run(['openssl', 'genpkey', '-algorithm', 'ED25519', '-outform', 'DER', '-out', str(private)], check=True, capture_output=True)
            seed = private.read_bytes()[-32:]
            public = subprocess.check_output(['openssl', 'pkey', '-in', str(private), '-inform', 'DER', '-pubout', '-outform', 'DER'])
            (root / 'public.der').write_bytes(public)
            config = root / 'apps/macos/Configuration'
            config.mkdir(parents=True)
            (config / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleShortVersionString': '1.0.0', 'CFBundleVersion': '12', 'SUPublicEDKey': base64.b64encode(public[-32:]).decode()}))
            assets = root / 'assets'; assets.mkdir()
            (assets / 'Twinvia-1.0.0-android-preview.apk').write_bytes(b'synthetic-apk')
            (assets / 'Twinvia-1.0.0-macos-arm64-preview.zip').write_bytes(b'synthetic-mac')
            with patch.object(module, 'ROOT', root):
                module.sign_release(assets, '1.0.0', seed)
                with self.assertRaises(ValueError):
                    module.sign_release(assets, '1.0.0', bytes(32))
            manifest_path = assets / 'update-manifest.json'
            payload = root / 'signed-payload'
            payload.write_bytes(b'Twinvia Android Update v1\x00' + manifest_path.read_bytes())
            signature = root / 'signature'
            signature.write_bytes(base64.b64decode((assets / 'update-manifest.sig').read_text()))
            command = ['openssl', 'pkeyutl', '-verify', '-rawin', '-pubin', '-inkey', str(root / 'public.der'), '-keyform', 'DER', '-sigfile', str(signature), '-in', str(payload)]
            subprocess.run(command, check=True, capture_output=True)
            manifest = json.loads(manifest_path.read_text()); self.assertEqual(manifest['build'], 12)
            payload.write_bytes(payload.read_bytes() + b' ')
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
