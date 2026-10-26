#!/usr/bin/env python3
"""Reject non-product files and obvious credentials before staging or publishing."""
import argparse
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
ROOT_FILES = {
    ".editorconfig", ".gitattributes", ".gitignore", ".swift-format", ".gitlab-ci.yml",
    "README.md", "CONTRIBUTING.md", "SECURITY.md", ".gitleaks.toml",
}
DOCS = {"architecture.md", "development.md", "testing.md", "ble-transport.md", "clipboard-sync.md", "branding.md", "releasing.md", "transports.md", "roadmap.md", "github-security.md"}
SCRIPTS = {
    "common.sh", "build-android.sh", "build-macos.sh", "build-ble-helper.py",
    "build-clipboard-helper.py", "prepare-nearby-sdk.py", "sign-macos.py",
    "install-android.sh", "enable-clipboard.py", "doctor.sh", "test.sh",
    "test-ble-pairing.py", "test-clipboard.py", "measure-bridge-resources.py",
    "check-publication.py", "format-code.py", "check.sh", "setup-android-ci.sh", "generate-brand-assets.swift",
    "package-release.py",
    "install-security-tools.py", "check-security.py",
}
GENERATED = {".git", ".tooling", ".artifacts", ".gradle", ".kotlin", "build", ".build", ".swiftpm", "DerivedData", "__pycache__", "xcuserdata"}
FORBIDDEN_SUFFIXES = {".p12", ".pfx", ".key", ".pem", ".keystore", ".jks", ".mobileprovision", ".provisionprofile", ".pcap", ".pcapng", ".ips", ".log", ".apk", ".aab", ".zip", ".db"}
SECRETS = [
    re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----"),
    re.compile(rb"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|glpat-[A-Za-z0-9_-]{20,}|AKIA[A-Z0-9]{16})\b"),
]


def candidates(root: Path) -> list[str]:
    result = subprocess.check_output(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=root,
    )
    return sorted(set(result.decode().split("\0")) - {""})


def permitted(name: str) -> bool:
    path = PurePosixPath(name)
    if any(part in GENERATED for part in path.parts) or path.name == "local.properties":
        return False
    if path.suffix.lower() in FORBIDDEN_SUFFIXES or path.name.startswith(".env"):
        return False
    if name in ROOT_FILES:
        return True
    if name in {".github/CODEOWNERS", ".github/dependabot.yml", ".github/pull_request_template.md", ".github/security-tools.json", ".github/codeql/codeql-config.yml"}:
        return True
    if name.startswith(".github/ISSUE_TEMPLATE/") and path.suffix == ".yml":
        return True
    if path.parts[:1] == ("docs",):
        return len(path.parts) == 2 and path.name in DOCS
    if path.parts[:1] == ("scripts",):
        return (len(path.parts) == 2 and path.name in SCRIPTS) or (
            path.parts[:2] == ("scripts", "tests") and path.suffix == ".py"
        )
    return name.startswith((
        "apps/android/", "apps/macos/", "shared/protocol/", ".github/workflows/",
        "tools/clipboard-helper/", "tools/clipboard-probe/", "vendor/nearby/", "assets/brand/",
    ))


def problems(root: Path) -> list[str]:
    issues = []
    for name in candidates(root):
        path = root / name
        if not path.exists() and not path.is_symlink():
            continue  # staged removal
        if not permitted(name):
            issues.append(f"Non-product or generated path: {name}")
            continue
        if path.is_symlink():
            issues.append(f"Symlink requires explicit review: {name}")
            continue
        if path.stat().st_size > 1_048_576:
            issues.append(f"Unexpected large source file: {name}")
            continue
        content = path.read_bytes()
        if any(pattern.search(content) for pattern in SECRETS):
            issues.append(f"Possible credential material: {name}")
    return issues


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    args = parser.parse_args()
    issues = problems(args.root)
    for issue in issues:
        print(issue, file=sys.stderr)
    if issues:
        return 1
    print("Publication scope and credential checks passed (not a complete secret audit).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
