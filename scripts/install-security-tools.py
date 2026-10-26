#!/usr/bin/env python3
"""Install reviewed CLI tools under ignored local tooling, verifying committed archive hashes."""
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import platform
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
INSTALL = ROOT / ".tooling/security-tools/bin"


def binary_from_archive(data: bytes, tool: str) -> bytes:
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        matches = [member for member in archive.getmembers() if PurePosixPath(member.name).name == tool]
        if len(matches) != 1 or not matches[0].isfile() or matches[0].size > 100_000_000:
            raise ValueError("Archive must contain one bounded regular tool binary")
        member = matches[0]
        path = PurePosixPath(member.name)
        if path.is_absolute() or ".." in path.parts:
            raise ValueError("Unsafe archive path")
        with archive.extractfile(member) as source:
            return source.read()


def main() -> None:
    machine = {"aarch64": "arm64", "amd64": "x86_64"}.get(platform.machine().lower(), platform.machine().lower())
    host = platform.system().lower() + "-" + machine
    config = json.loads((ROOT / ".github/security-tools.json").read_text())
    INSTALL.mkdir(parents=True, exist_ok=True)
    for tool, settings in config.items():
        asset = settings["assets"].get(host)
        if asset is None:
            raise SystemExit("Unsupported security-tool host: " + host)
        destination = INSTALL / tool
        marker = INSTALL / (tool + ".verified.json")
        if destination.is_file() and marker.is_file():
            recorded = json.loads(marker.read_text())
            if recorded.get("archive_sha256") == asset["sha256"] and recorded.get("binary_sha256") == hashlib.sha256(destination.read_bytes()).hexdigest():
                print(tool + " " + settings["version"] + " verified (cached)")
                continue
        request = urllib.request.Request(asset["url"], headers={"User-Agent": "Twinvia-security-tool-setup"})
        with urllib.request.urlopen(request, timeout=60) as response:
            data = response.read(100_000_001)
        if len(data) > 100_000_000 or hashlib.sha256(data).hexdigest() != asset["sha256"]:
            raise ValueError("Tool archive size/checksum mismatch: " + tool)
        binary = binary_from_archive(data, tool)
        temporary = destination.with_suffix(".tmp")
        temporary.write_bytes(binary)
        temporary.chmod(0o755)
        os.replace(temporary, destination)
        marker.write_text(json.dumps({"archive_sha256": asset["sha256"], "binary_sha256": hashlib.sha256(binary).hexdigest()}) + "\n")
        print(tool + " " + settings["version"] + " verified and installed")


if __name__ == "__main__":
    main()
