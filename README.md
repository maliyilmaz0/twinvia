![Twinvia — Two devices. One flow.](assets/brand/banner.svg)

# Twinvia

A native Android application and macOS menu-bar companion for notifications, clipboard synchronization, files, and phone controls over Bluetooth LE.

**Version 0.9.0 · Developer preview.** The applications communicate locally through Google Nearby Connections and a certificate-pinned TLS session. A shared Wi-Fi network, hotspot, or cloud relay is not required for application traffic. Internet access is needed to download build dependencies; Android also requires Google Play services.

See the [transport comparison and requirements](docs/transports.md) for why this preview uses BLE, what Wi-Fi Aware/AWDL/USB would change, and the Apple platform-support discussion.

## Features and limitations

| Feature | Available behavior |
| --- | --- |
| Pairing | Scan a five-minute QR invitation; save trust and reconnect automatically. |
| Notifications | Native macOS notifications, Android app-icon attachments, per-app filters, duplicate suppression, and supported reply/dismiss actions. The sender remains Twinvia. |
| Clipboard | Automatic text/URL synchronization in both directions; Mac PNG/TIFF screenshots to the Android image clipboard. Android background access requires the optional USB-activated helper described below. |
| Files | Approved, SHA-256-verified transfers in both directions; progress and cancellation. One transfer at a time, no resume or queue. |
| Phone data | Paginated contacts, call history, and shared-storage browsing with separate Android permissions. Private application storage is excluded. |
| Controls | Battery/charging/lock status, media controls, and a time-limited phone ringer. |
| Calls | Call notifications, supported answer/end controls, and separate Bluetooth HFP dialing. Reliable Mac cellular-call audio is not provided by this BLE build. |

BLE prioritizes small messages over throughput. In one device trial, a 116,608-byte PNG took about 18 seconds; a 64 KiB file completed an integrity-checked round trip. The protocol's 2 GiB ceiling is a validation limit, **not** a practical large-file speed claim. Reconnection can take tens of seconds after radio failure. Do not use this preview as a critical calling service.

Not implemented: Apple Messages integration, registration of an Android line in Apple's Phone app, SMS history management, Android-to-Mac image clipboard, remote screen control, or production PCM audio over BLE.

## Upcoming features

The next priorities are easier clipboard setup and recovery, stable signed installers, a unified remote phone-management interface, file-transfer queues/resume, and richer phone-data navigation. Later work includes Android-to-Mac image clipboard, optional multi-device support, and a consent-based remote-screen/control prototype on a suitable faster transport.

Screen control, reliable cellular-call audio, and public Mac Wi-Fi Aware support still need platform feasibility work. They are not available in the current release or guaranteed for the next version. Read the [prioritized roadmap and completion criteria](docs/roadmap.md), [clipboard options](docs/clipboard-sync.md#improvement-options), and [transport requirements](docs/transports.md).

## Requirements

- **Mac:** macOS 14 or later and Bluetooth LE. Apple Silicon is the currently tested build architecture.
- **Phone:** Android 13 / API 33 or later, Google Play services, and Bluetooth LE.
- **Development:** full Xcode with Swift 6, JDK **21**, Python 3.10+, Git, Android SDK platform **36**, build tools **36.0.0**, and platform tools.
- Grant Bluetooth/Nearby Devices permission on both devices. Android may also request Nearby Wi-Fi permission as required by the SDK. This does not enable a shared-network transport.

The current device checks used a Galaxy S24 FE running Android 17 / One UI 9 and an Apple Silicon Mac. Other vendors, extended Doze/sleep behavior, and unplugged battery life require additional validation. No administrator helper or system-security modification is part of the product build.

## Build

Prebuilt developer-preview packages are available under [GitHub Releases](https://github.com/maliyilmaz0/twinvia/releases). Read the [download, signing, and upgrade notes](docs/releasing.md) before installing. The current preview APK is debug-signed; the Mac archive is ad-hoc signed and not notarized.

Clone the repository, then run these commands from its root:

```sh
gh repo clone maliyilmaz0/twinvia
cd twinvia
```

```sh
export JAVA_HOME="$(/usr/libexec/java_home -v 21)"
export ANDROID_HOME="$HOME/Library/Android/sdk"
./scripts/doctor.sh
./scripts/build-android.sh
./scripts/build-macos.sh
```

Use **JDK 21** for Android Studio's Gradle JVM. The wrapper verifies its Gradle distribution checksum. An emulator is optional for UI work; real Bluetooth integration tests need a physical phone and Mac.

Build outputs:

```text
.artifacts/android/Twinvia-debug.apk
.artifacts/android/TwinviaClipboardHelper.jar
.artifacts/macos/Twinvia.app
```

The Mac script fetches a pinned Google Nearby revision and applies the product patch in `vendor/nearby/`. It builds the Bluetooth helper before packaging it inside the app. A Developer ID Application identity is used when available; set `TWINVIA_SIGNING_IDENTITY=-` for an ad-hoc development build. CI artifacts are development builds, not notarized installers. Ad-hoc signing can change permission identity across builds.

See [development](docs/development.md) for IDE setup, signing, CI runners, and contributor commands.

## Install and pair

1. Install the APK on your phone using Android Studio, or run `./scripts/install-android.sh` with a USB-debugging-authorized phone connected.
2. Copy `.artifacts/macos/Twinvia.app` into `/Applications`, then launch it. The app lives in the menu bar; closing its control-center window keeps it running. **Quit** quits it.
3. Open Twinvia on the phone, grant Nearby Devices/Bluetooth access, and scan the QR displayed on the Mac. Do not share screenshots of that QR: it contains a temporary pairing secret.
4. Grant notification access under Android Settings → Special app access → Notification access. Allow Twinvia notifications in macOS System Settings → Notifications.
5. Keep Bluetooth enabled. Saved trust is reused after application restarts and radio interruptions; rescanning a QR is not part of normal reconnection.

For phone-data browsing, grant contacts and call-log permission separately. Shared-storage browsing requires All files access; grant it only if you want that feature. Notification reply availability depends on the source app and the phone's lock state.

### Automatic clipboard

Android restricts background clipboard access. The optional helper runs under the ADB shell identity and connects only to the app's authenticated loopback endpoint. It does not root the phone or change the app's UID.

With your unlocked phone connected over USB and USB debugging authorized:

```sh
python3 scripts/enable-clipboard.py
```

Then copy and paste normally. USB is used for activation, not as the bridge data transport. Reactivate the helper after a phone reboot. Clipboard sharing pauses when the phone is locked or the bridge disconnects and resumes after reconnection. You can disable synchronization in either app. The helper has elevated clipboard access compared with a normal APK; install it only on a device you control. See [clipboard setup and privacy](docs/clipboard-sync.md).

## Troubleshooting

| Symptom | Check |
| --- | --- |
| No connection | Bluetooth and Nearby Devices permissions; Google Play services; both apps running. Allow time for discovery/backoff, then use the retry control. |
| Keychain prompt on Mac | Use the visible pairing-key access action and approve the system dialog. A denied read preserves existing trust instead of silently replacing it. |
| Clipboard does not move | Unlock the phone; check synchronization is enabled and the helper is ready. Reactivate after phone reboot. |
| Image/file transfer is slow | BLE bandwidth is limited. Keep devices close and wait for acknowledgement; large transfers are experimental. |
| Notification missing | Grant both notification permissions, check app filters and persistent-notification filtering, and check macOS Focus settings. |
| Calls still use the phone | Data pairing does not configure HFP audio. Reliable audio relay is outside this build's supported features. |

## Code and verification

```text
apps/android/app/                 Android UI and platform integrations
apps/android/core/protocol/       Platform-independent Kotlin wire contract
apps/macos/Sources/Twinvia/     App, Connection, Features, and UI layers
apps/macos/BluetoothBridge/      Isolated ordinary-permission BLE helper
shared/protocol/                 Swift contract, JSON schemas, shared fixtures
tools/clipboard-helper/          Optional Android clipboard adapter
tools/clipboard-probe/           Synthetic device-test utility
vendor/nearby/                   Pinned dependency patch and provenance
scripts/                        Build, quality, installation, and test entry points
```

```sh
python3 scripts/format-code.py          # Apply Swift/Kotlin formatting
./scripts/check.sh                     # Formatting, publication policy, tooling tests
./scripts/test.sh --console=plain       # Swift + Kotlin/Android unit tests
./scripts/build-android.sh              # Android unit tests, lint, APK
./scripts/build-macos.sh                # Helper and packaged Mac application
```

- [Architecture and code responsibilities](docs/architecture.md)
- [Development and CI](docs/development.md)
- [Test strategy and device checks](docs/testing.md)
- [BLE transport and security boundaries](docs/ble-transport.md)
- [Alternative transports, requirements, and Apple feedback](docs/transports.md)
- [Upcoming features and implementation priorities](docs/roadmap.md)
- [Brand assets and compatibility](docs/branding.md)
- [Contributing](CONTRIBUTING.md)

GitHub Actions and GitLab CI configurations build development artifacts and preserve test/lint reports. A separate, manually dispatched GitHub workflow publishes developer previews from successful main-branch CI runs; it does not upload signing keys. See [release operations](docs/releasing.md). Private investigations, local captures, certificates, installed dependencies, and build outputs are excluded from source publication. Run `python3 scripts/check-publication.py` before staging and pushing. Its checks complement manual review; they are not a complete secret audit.
