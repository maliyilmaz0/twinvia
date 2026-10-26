#!/usr/bin/env python3
"""Package only explicit preview binaries from a successful CI run; never walk local build state."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import re
import shutil
from zipfile import ZipFile, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[1]


def inspect_mac(path: Path) -> str:
    with ZipFile(path) as archive:
        names = set(archive.namelist())
        for name in names:
            p = PurePosixPath(name)
            if p.is_absolute() or ".." in p.parts or "\\" in name:
                raise ValueError("Unsafe Mac archive path")
            if not (name.startswith("Twinvia.app/") or name.startswith("__MACOSX/")):
                raise ValueError("Unexpected Mac archive root")
            if any(part in {"NativePeerDiscovery.app", "neighbor-advertise", "nan-tcp-relay"} for part in p.parts):
                raise ValueError("Private research helper in Mac archive")
        required = {
            "Twinvia.app/Contents/Info.plist",
            "Twinvia.app/Contents/MacOS/Androfest",
            "Twinvia.app/Contents/Resources/AndrofestBluetooth.app/Contents/MacOS/AndrofestBleBridge",
        }
        if not required.issubset(names):
            raise ValueError("Mac application or BLE helper is missing")
        info = plistlib.loads(archive.read("Twinvia.app/Contents/Info.plist"))
        if info.get("CFBundleIdentifier") != "dev.androfest.macos":
            raise ValueError("Unexpected Mac bundle identity")
        return info["CFBundleShortVersionString"]


def package(inputs: Path, output: Path, run_id: str, commit: str, repository: str) -> str:
    if not re.fullmatch(r"[1-9][0-9]*", run_id) or not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("Invalid source run or commit")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Invalid repository")
    version = plistlib.loads((ROOT / "apps/macos/Configuration/Info.plist").read_bytes())["CFBundleShortVersionString"]
    android_config = (ROOT / "apps/android/app/build.gradle.kts").read_text()
    android_version = re.search(r'versionName\s*=\s*"([^"]+)"', android_config)
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version) or android_version is None or android_version[1] != version:
        raise ValueError("Platform source versions do not agree")
    mac = inputs / "macos/Twinvia-macos.zip"
    apk = inputs / "android/.artifacts/android/Twinvia-debug.apk"
    jar = inputs / "android/.artifacts/android/AndrofestClipboardHelper.jar"
    if inspect_mac(mac) != version:
        raise ValueError("Mac artifact version does not match source")
    with ZipFile(apk) as archive:
        if not {"AndroidManifest.xml", "classes.dex"}.issubset(archive.namelist()):
            raise ValueError("Android artifact is not an APK")
    with ZipFile(jar) as archive:
        if "classes.dex" not in archive.namelist():
            raise ValueError("Clipboard helper has no Android bytecode")
    # A fresh directory prevents stale files from a previous release being uploaded.
    output.mkdir(parents=True, exist_ok=False)
    shutil.copyfile(mac, output / f"Twinvia-{version}-macos-arm64-preview.zip")
    shutil.copyfile(apk, output / f"Twinvia-{version}-android-preview.apk")
    with ZipFile(output / f"Twinvia-{version}-clipboard-helper.zip", "w", ZIP_DEFLATED) as kit:
        kit.write(jar, "TwinviaClipboardHelper/AndrofestClipboardHelper.jar")
        kit.write(ROOT / "scripts/enable-clipboard.py", "TwinviaClipboardHelper/enable-clipboard.py")
        kit.writestr("TwinviaClipboardHelper/README.txt", (
            "Twinvia optional clipboard helper\n\n"
            "Install the matching preview APK, unlock the phone, enable USB debugging, and authorize your computer.\n"
            "Install Python 3 and Android platform-tools (adb). In this folder run:\n"
            "python3 enable-clipboard.py\n\n"
            "The prebuilt JAR is used automatically; no JDK or Android SDK build is needed.\n"
            "Use --adb /path/to/adb or --serial DEVICE if needed. Reactivate after a phone reboot.\n"
            "The helper runs as the ADB shell user and can access clipboard contents. Use only on your own device.\n"
        ))
    metadata = {
        "version": version, "channel": "developer-preview", "repository": repository,
        "source_commit": commit, "ci_run_id": run_id,
        "ci_run_url": f"https://github.com/{repository}/actions/runs/{run_id}",
        "macos": {"architecture": "arm64", "signing": "ad-hoc", "notarized": False},
        "android": {"variant": "debug", "signing": "CI debug key"},
    }
    (output / "build-info.json").write_text(json.dumps(metadata, indent=2) + "\n")
    files = sorted(output.iterdir())
    (output / "SHA256SUMS").write_text("".join(
        hashlib.sha256(p.read_bytes()).hexdigest() + "  " + p.name + "\n" for p in files
    ))
    return version


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inputs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--repository", required=True)
    args = parser.parse_args()
    print(package(args.inputs, args.output, args.run_id, args.commit, args.repository))
