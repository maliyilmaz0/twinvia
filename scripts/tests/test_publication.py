import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("publication", ROOT / "scripts/check-publication.py")
publication = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publication)


class PublicationTests(unittest.TestCase):
    def test_research_and_generated_paths_are_never_publishable(self):
        for name in ("tools/native-peer/discovery.m", "tools/research/notes.md", "docs/continuity-security-research.md",
                     "scripts/inspect-peer-policy.py", "apps/android/local.properties", "apps/android/app/build/result.json",
                     ".artifacts/results.json", "signing.p12", ".env", "apps/macos/key.pem"):
            with self.subTest(name=name):
                self.assertFalse(publication.permitted(name))

    def test_product_sources_are_publishable(self):
        for name in ("README.md", "apps/macos/BluetoothBridge/Package.swift", "vendor/nearby/ble-transport.patch",
                     "tools/clipboard-helper/src/ClipboardAgent.java", "docs/testing.md", "scripts/tests/test_publication.py"):
            self.assertTrue(publication.permitted(name), name)

    def test_force_staged_ignored_file_and_secret_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            (root / ".gitignore").write_text("/tools/*\n")
            research = root / "tools/native-peer/data.txt"
            research.parent.mkdir(parents=True)
            research.write_text("local notes")
            subprocess.run(["git", "add", "--force", "tools/native-peer/data.txt"], cwd=root, check=True)
            (root / "README.md").write_text("-----BEGIN " + "PRIVATE KEY-----\nfixture\n")
            issues = publication.problems(root)
            self.assertTrue(any("Non-product" in issue for issue in issues))
            self.assertTrue(any("credential" in issue for issue in issues))

    def test_gitignore_excludes_private_work_but_keeps_product_dependencies(self):
        names = ["docs/native-peer-policy.md", "tools/nearby-probe/README.md", "scripts/probe-native-peer.py",
                 "vendor/nearby/ble-transport.patch", "apps/macos/BluetoothBridge/Package.swift", "README.md"]
        result = subprocess.run(["git", "check-ignore", "--no-index", "--stdin"], cwd=ROOT,
                                input="\n".join(names) + "\n", capture_output=True, text=True)
        self.assertIn(result.returncode, (0, 1))
        self.assertEqual(set(result.stdout.splitlines()), set(names[:3]))


if __name__ == "__main__":
    unittest.main()
