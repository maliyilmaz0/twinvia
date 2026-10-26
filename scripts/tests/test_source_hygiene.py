import ast
import importlib.util
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("publication", ROOT / "scripts/check-publication.py")
publication = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publication)


class SourceHygieneTests(unittest.TestCase):
    def test_publishable_python_and_shell_syntax(self):
        for name in publication.candidates(ROOT):
            if not publication.permitted(name):
                continue
            path = ROOT / name
            with self.subTest(path=name):
                if path.suffix == ".py":
                    ast.parse(path.read_text(), filename=name)
                elif path.suffix == ".sh":
                    result = subprocess.run(["bash", "-n", str(path)], capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stderr)

    def test_local_document_links_stay_inside_publishable_source(self):
        for name in publication.candidates(ROOT):
            if not publication.permitted(name) or not name.endswith(".md"):
                continue
            for link in re.findall(r"\]\(([^)]+)\)", (ROOT / name).read_text()):
                if "://" in link or link.startswith("#"):
                    continue
                target = (ROOT / name).parent / link.split("#", 1)[0]
                with self.subTest(document=name, link=link):
                    self.assertTrue(target.exists(), "Broken relative documentation link")
                    self.assertTrue(publication.permitted(target.resolve().relative_to(ROOT).as_posix()),
                                    "Documentation must not link to private local investigations")


if __name__ == "__main__":
    unittest.main()
