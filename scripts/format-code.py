#!/usr/bin/env python3
"""Format/check only publishable Swift and Kotlin sources with pinned ktfmt."""
import argparse
import hashlib
import importlib.util
import os
from pathlib import Path
import subprocess
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
KTFMT_VERSION = "0.63"
KTFMT_SHA256 = "a015521ddb1c7a80c41edb56b91b4a231439592ffd2e85ac866ff8134c37c112"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--language", choices=("swift", "kotlin", "all"), default="all")
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location("publication", ROOT / "scripts/check-publication.py")
    publication = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(publication)
    files = [ROOT / name for name in publication.candidates(ROOT) if publication.permitted(name) and (ROOT / name).is_file()]
    if args.language in ("swift", "all"):
        swift = [str(path) for path in files if path.suffix == ".swift"]
        if swift:
            command = ["xcrun", "swift-format", "lint", "--strict"] if args.check else ["xcrun", "swift-format", "format", "--in-place"]
            subprocess.run([*command, "--configuration", str(ROOT / ".swift-format"), *swift], check=True)
    if args.language in ("kotlin", "all"):
        jar = ROOT / f".tooling/ktfmt-{KTFMT_VERSION}.jar"
        if not jar.exists():
            jar.parent.mkdir(parents=True, exist_ok=True)
            url = f"https://repo.maven.apache.org/maven2/com/facebook/ktfmt/{KTFMT_VERSION}/ktfmt-{KTFMT_VERSION}-with-dependencies.jar"
            with urllib.request.urlopen(url, timeout=60) as response:
                data = response.read()
            if hashlib.sha256(data).hexdigest() != KTFMT_SHA256:
                raise SystemExit("ktfmt download checksum mismatch")
            jar.write_bytes(data)
        if hashlib.sha256(jar.read_bytes()).hexdigest() != KTFMT_SHA256:
            raise SystemExit("Cached ktfmt checksum mismatch")
        kotlin = [str(path) for path in files if path.suffix in (".kt", ".kts")]
        java = str(Path(os.environ["JAVA_HOME"]) / "bin/java") if os.environ.get("JAVA_HOME") else "java"
        options = ["--kotlinlang-style"] + (["--dry-run", "--set-exit-if-changed"] if args.check else [])
        if kotlin:
            subprocess.run([java, "-jar", str(jar), *options, *kotlin], check=True)


if __name__ == "__main__":
    main()
