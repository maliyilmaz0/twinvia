#!/usr/bin/env python3
"""Run local-only workflow/Python correctness checks and redacted full-history secret scanning."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / ".tooling/security-tools/bin"


def main() -> None:
    if not all((TOOLS / name).is_file() for name in ["gitleaks", "actionlint", "ruff"]):
        raise SystemExit("Run python3 scripts/install-security-tools.py first")
    # Tracked product files only: never scan/upload the ignored research or device state.
    files = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).decode().split("\0")
    python = [name for name in files if name.endswith(".py")]
    subprocess.run([str(TOOLS / "ruff"), "check", "--no-cache", "--select", "E9,F821,F822,F823", "--", *python], cwd=ROOT, check=True)
    subprocess.run([str(TOOLS / "actionlint"), "-color"], cwd=ROOT, check=True)
    subprocess.run([str(TOOLS / "gitleaks"), "git", "--config", ".gitleaks.toml", "--redact=100", "--no-banner", "--log-opts=--all"], cwd=ROOT, check=True)
    subprocess.run([str(TOOLS / "gitleaks"), "git", "--config", ".gitleaks.toml", "--redact=100", "--no-banner", "--pre-commit", "--staged"], cwd=ROOT, check=True)
    print("Security/quality checks passed; this is not a complete security audit.")


if __name__ == "__main__":
    main()
