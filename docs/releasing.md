# Twinvia 0.9.0 — Developer Preview

Two devices. One flow. This preview provides encrypted Bluetooth LE pairing, native Mac notifications, automatic text clipboard synchronization, Mac-to-Android image clipboard, file transfers, contacts/call-history browsing, and supported phone controls. A shared Wi-Fi network or hotspot is not required for app traffic.

## Downloads and installation

- **Android:** download `Twinvia-0.9.0-android-preview.apk` and install it on Android 13 or later with Google Play services. Grant installation permission only to the application you use to open the APK.
- **Mac:** download `Twinvia-0.9.0-macos-arm64-preview.zip`, extract it, and copy `Twinvia.app` to Applications. This package is for Apple Silicon and macOS 14 or later. Launch it from Applications; its controls live in the menu bar.
- **Optional Android background clipboard:** extract `Twinvia-0.9.0-clipboard-helper.zip`. Install Python 3 and Android platform-tools, unlock the phone, authorize USB debugging, and run `python3 enable-clipboard.py` from the extracted `TwinviaClipboardHelper` directory. It uses the included JAR; a JDK/build SDK is unnecessary. Use `--adb /path/to/adb` or `--serial DEVICE` when needed. Reactivate after a phone reboot.

Open Twinvia on both devices and scan the Mac's temporary pairing QR with the phone. Allow Bluetooth/Nearby Devices and notification access. Contacts, call history, and shared storage have separate permissions. Clipboard sharing pauses when the phone is locked. The optional helper runs as the ADB shell user and has more clipboard access than an ordinary APK; use it only on a device you control.

## Preview signing and limitations

These are the exact development binaries from a successful GitHub CI run, packaged without recompiling. `build-info.json` identifies the source commit, CI run, architecture, and signing status. `SHA256SUMS` covers every downloadable binary and that metadata file. Verify downloaded files with `shasum -a 256 -c SHA256SUMS` on macOS or `sha256sum -c SHA256SUMS` on Linux, with all assets in the same directory.

The APK uses that CI runner's **debug signing key** and is debuggable. It may not update an APK installed by Android Studio or another CI run. Do not uninstall a daily installation merely to resolve a signature mismatch: that loses app data and pairing state. Build with your existing key or use a separate test device. Stable release-key signing is a separate distribution step.

The Mac archive is **ad-hoc signed and not notarized**. Gatekeeper may block it; this preview does not promise a frictionless installation. Do not disable SIP, AMFI, or other system protections. A normally Developer ID-signed, hardened, notarized build is needed before general Mac distribution. The source build can use an installed Developer ID identity. macOS may request permissions again after a signing-identity change.

BLE bandwidth is limited. Large file transfers are experimental, and reconnection can take tens of seconds. Reliable Mac cellular-call audio, Apple Messages integration, Android-to-Mac image clipboard, and remote screen control are not included. The optional clipboard helper remains necessary for automatic Android background clipboard access. See the repository README for full setup and limitations.

## Maintainer release procedure

1. Push the reviewed product changes to `main` and wait for **Build and test** to pass. Every dependency action is pinned to a commit.
2. Run **Publish developer preview** manually from `main`, supplying that successful run's numeric ID. Only a completed, successful `ci.yml` run from a push to this repository's `main` is accepted. Pull-request and foreign-repository artifacts are rejected.
3. The release workflow checks out the CI source commit, downloads only the named build artifacts, packages an explicit binary allowlist, and creates a version tag/release draft. Existing tags/releases are never overwritten.
4. It uploads five assets, downloads them again, verifies checksums, then publishes the prerelease. Any failure before publication leaves a draft for inspection. Resolve that draft explicitly before retrying; the workflow does not replace assets silently.

Ordinary CI uses `contents: read`. Only the manual publishing job has `actions: read` and `contents: write`. It uses the temporary `GITHUB_TOKEN`, not a stored personal token; checkout does not persist credentials. No signing certificate, keystore, or notarization password is uploaded. GitHub's default workflow token remains read-only and cannot approve pull requests.

The repository remains private until its owner chooses public visibility. Branch protection on a private repository may require a paid GitHub plan; enable required `publication`, `android`, and `macos` checks when the repository/plan supports it. Choose a license for Twinvia before public source distribution. Dependency licenses remain their respective owners' terms; the Mac BLE helper includes upstream notices. A prerelease is a tested preview, not a production-readiness or security guarantee.
