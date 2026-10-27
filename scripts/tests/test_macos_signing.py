"""Exercise nested signing against actual unsigned Mach-O code on macOS."""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(sys.platform == 'darwin' and shutil.which('codesign'), 'Requires native macOS signing')
class MacSigningTests(unittest.TestCase):
    def test_signs_unsigned_debug_libraries_before_outer_bundle(self):
        with tempfile.TemporaryDirectory(prefix='twinvia-signing-') as directory:
            app = Path(directory) / 'SigningFixture.app'
            contents = app / 'Contents'
            binaries = contents / 'MacOS'
            binaries.mkdir(parents=True)
            (contents / 'Info.plist').write_bytes(plistlib.dumps({
                'CFBundleIdentifier': 'dev.twinvia.signing-fixture',
                'CFBundleExecutable': 'SigningFixture',
                'CFBundlePackageType': 'APPL',
            }))
            for name, options, source in [
                ('SigningFixture', [], 'int main(void) { return 0; }'),
                ('__preview.dylib', ['-dynamiclib'], 'int preview(void) { return 1; }'),
                ('SigningFixture.debug.dylib', ['-dynamiclib'], 'int debug(void) { return 2; }'),
            ]:
                subprocess.run(['xcrun', 'clang', '-x', 'c', *options, '-Wl,-no_adhoc_codesign',
                                '-o', str(binaries / name), '-'], input=source, text=True,
                               capture_output=True, check=True)
            unsigned = subprocess.run(['codesign', '--verify', str(binaries / '__preview.dylib')],
                                      capture_output=True)
            self.assertNotEqual(unsigned.returncode, 0, 'Fixture must start unsigned')
            subprocess.run([sys.executable, str(ROOT / 'scripts/sign-macos.py'), str(app)],
                           env={**os.environ, 'TWINVIA_SIGNING_IDENTITY': '-'},
                           capture_output=True, check=True)
            for target in [app, binaries / '__preview.dylib', binaries / 'SigningFixture.debug.dylib']:
                subprocess.run(['codesign', '--verify', '--deep', '--strict', str(target)],
                               capture_output=True, check=True)
