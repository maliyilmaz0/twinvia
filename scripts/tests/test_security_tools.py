import importlib.util
import io
from pathlib import Path
import tarfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("security_tools", ROOT / "scripts/install-security-tools.py")
tools = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tools)


class SecurityToolArchiveTests(unittest.TestCase):
    def archive(self, names, symlink=False):
        data = io.BytesIO()
        with tarfile.open(fileobj=data, mode="w:gz") as archive:
            for name in names:
                member = tarfile.TarInfo(name)
                if symlink:
                    member.type = tarfile.SYMTYPE
                    member.linkname = "/unexpected"
                    archive.addfile(member)
                else:
                    member.size = 4
                    archive.addfile(member, io.BytesIO(b"tool"))
        return data.getvalue()

    def test_extracts_only_the_selected_regular_binary(self):
        data = self.archive(["license.txt", "release/ruff"])
        self.assertEqual(tools.binary_from_archive(data, "ruff"), b"tool")

    def test_rejects_traversal_absolute_duplicate_missing_and_symlink(self):
        for names, symlink in [(["../ruff"], False), (["/ruff"], False),
                               (["one/ruff", "two/ruff"], False), (["other"], False), (["ruff"], True)]:
            with self.subTest(names=names, symlink=symlink), self.assertRaises(ValueError):
                tools.binary_from_archive(self.archive(names, symlink), "ruff")


if __name__ == "__main__":
    unittest.main()
