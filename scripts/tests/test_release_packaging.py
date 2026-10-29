import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("release_packaging", ROOT / "scripts/package-release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleasePackagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.inputs = Path(self.temp.name) / "inputs"
        self.output = Path(self.temp.name) / "release"
        self.mac = self.inputs / "macos/Twinvia-macos.zip"
        self.mac.parent.mkdir(parents=True)
        self.write_mac()
        android = self.inputs / "android/.artifacts/android"
        android.mkdir(parents=True)
        with ZipFile(android / "Twinvia-debug.apk", "w") as archive:
            archive.writestr("AndroidManifest.xml", b"test fixture")
            archive.writestr("classes.dex", b"test fixture")
        with ZipFile(android / "TwinviaClipboardHelper.jar", "w") as archive:
            archive.writestr("classes.dex", b"test fixture")
        (android / "private-capture.txt").write_text("must not ship")

    def write_mac(self, version="0.9.0", extra=None, helper=True, legacy=False, build="11"):
        executable = "Androfest" if legacy else "Twinvia"
        helper_name = "Androfest" if legacy else "Twinvia"
        with ZipFile(self.mac, "w") as archive:
            archive.writestr("Twinvia.app/Contents/Info.plist", plistlib.dumps({
                "CFBundleIdentifier": "dev.androfest.macos", "CFBundleShortVersionString": version,
                "CFBundleExecutable": executable, "CFBundleVersion": build,
            }))
            archive.writestr(f"Twinvia.app/Contents/MacOS/{executable}", b"test fixture")
            if helper:
                archive.writestr(f"Twinvia.app/Contents/Resources/{helper_name}Bluetooth.app/Contents/MacOS/{helper_name}BleBridge", b"fixture")
            if extra:
                archive.writestr(extra, b"must reject")

    def package(self, run_id="123"):
        return release.package(self.inputs, self.output, run_id, "a" * 40, "example/twinvia")

    def test_only_explicit_assets_ship_and_checksums_match(self):
        self.assertEqual(self.package(), "0.9.0")
        self.assertEqual(len(list(self.output.iterdir())), 5)
        for line in (self.output / "SHA256SUMS").read_text().splitlines():
            expected, name = line.split("  ")
            self.assertEqual(hashlib.sha256((self.output / name).read_bytes()).hexdigest(), expected)
        info = json.loads((self.output / "build-info.json").read_text())
        self.assertFalse(info["macos"]["notarized"])
        with ZipFile(self.output / "Twinvia-0.9.0-clipboard-helper.zip") as kit:
            self.assertEqual(len(kit.namelist()), 3)
            self.assertNotIn("private-capture.txt", " ".join(kit.namelist()))
        with self.assertRaises(FileExistsError):
            self.package()

    def test_research_and_unsafe_archive_entries_are_rejected(self):
        for extra in ["Twinvia.app/Contents/Resources/NativePeerDiscovery.app/helper", "../capture", "/absolute", "other.app/Info.plist"]:
            with self.subTest(extra=extra):
                self.write_mac(extra=extra)
                with self.assertRaises(ValueError):
                    self.package()
                self.assertFalse(self.output.exists())

    def test_missing_helper_and_mismatched_version_are_rejected(self):
        for options in [{"helper": False}, {"version": "0.8.0"}, {"build": "10"}]:
            with self.subTest(options=options):
                self.write_mac(**options)
                with self.assertRaises(ValueError):
                    self.package()

    def test_invalid_provenance_is_rejected(self):
        with self.assertRaises(ValueError):
            self.package(run_id="123; echo invalid")
        self.assertFalse(self.output.exists())

    def test_original_preview_artifacts_remain_inspectable(self):
        self.write_mac(legacy=True)
        android = self.inputs / "android/.artifacts/android"
        (android / "TwinviaClipboardHelper.jar").rename(android / "AndrofestClipboardHelper.jar")
        self.assertEqual(self.package(), "0.9.0")


if __name__ == "__main__":
    unittest.main()
