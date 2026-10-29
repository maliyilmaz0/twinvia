# Phone mirroring and control

This source-build prototype provides a dedicated, resizable SwiftUI phone window. Open **Screen → Open phone mirror**, the tray's **Phone mirror** button, or `twinvia://screen`. The window follows explicit opens to the current macOS Space and supports normal resizing/full screen. Closing it stops the screen lane and clears the image; minimizing pauses preview requests. Mac sleep closes the screen lane and clears the image; capture requires an explicit refresh after waking. The companion bridge remains available independently of the mirror window.

## Phone approval

1. Enable **Twinvia screen control** in Android Accessibility settings. The service declares screenshot, gesture and input-method capabilities. It does not read accessibility event contents, surrounding text or the UI tree.
2. On the phone, select **Start screen viewing** and approve its disclosure. A persistent notification offers **Stop sharing**. The lease lasts at most five minutes; lock/screen off, connection loss, service revocation or app-process exit ends it.
3. Approve **Enable touch control** separately to permit taps, swipes, keyboard input and navigation. Remote requests cannot start or extend either approval.
4. In the Mac mirror, refresh the screen. Click to tap, drag to swipe, or use Back/Home/Notifications. The keyboard button sends explicitly entered text (at most 1,024 UTF-16 units), Enter or Backspace to the focused phone editor through Android's public accessibility input connection. Some editors/OS versions may refuse input. Text is not logged or added to clipboard history.

## Image quality and preview

**Responsive** keeps the earlier 480-pixel long-edge JPEG path (at most 70,000 encoded bytes). **Detail** captures up to a 2,160-pixel long edge and compresses to at most 130,000 bytes. Wire metadata is limited to 2,560 pixels per edge and 4,194,304 total pixels. The Mac checks the actual JPEG dimensions against that metadata before decoding. Screen images remain in memory and are never saved by Twinvia.

Detail requires the `remote.screen.v2` capability. Older paired APKs keep the original screenshot path. BLE detail transfers can be slow; increasing JPEG resolution cannot create more radio bandwidth. The play/pause button requests the next image only after the prior response and a short delay, keeping at most one image in flight. This is a screenshot preview, not a MediaProjection/H.264 live-video implementation or a claimed 30/60 FPS stream.

## Optional faster Bluetooth lane — experimental

The bolt button opens a separate Bluetooth Classic/RFCOMM screenshot lane. Pair the phone through macOS Bluetooth settings, choose it in the mirror popup, and connect while the phone-approved viewing lease and existing BLE session are active. This uses public Android BluetoothSocket and Mac IOBluetooth APIs; it does not require a shared LAN, hotspot, USB debugging, SIP changes or private Wi-Fi APIs.

The existing certificate-pinned connection issues a fresh random 256-bit screen key and session ID. Only screen requests/responses use RFCOMM; phone controls remain on the existing connection, so an RFCOMM image does not fill the BLE application stream. The screen channel uses AES-256-GCM, distinct per-direction nonces, a session-bound authenticated context, strict monotonic counters and bounded frames. Replay, reflection, tampering and out-of-order records are rejected. A listener accepts one socket; unauthenticated sockets close after five seconds, discovery expires after fifteen seconds, and the normal phone lease bounds the whole session. The selected paired device still needs the application key before it can receive any screen image.

On screen-lane loss the preview pauses and the displayed image clears. The authenticated BLE pairing remains; the user may refresh over BLE or reconnect the faster lane. A failed experiment does not remove pairing or silently switch to a LAN.

**Validation limit:** the Android and Mac implementation, protocol interoperability vectors, tamper/replay tests, bounds and builds can be checked without a phone. RFCOMM reachability, actual throughput, coexistence with BLE/HFP, vendor input behavior and battery use require the physical phone. No speed/FPS improvement is claimed until measured on that device. Bluetooth Classic may still be insufficient for high-quality live video; a separately supported faster transport and Android MediaProjection/MediaCodec would be needed for that product goal.

This is Twinvia's own interface. It does not register Android as an iPhone in Apple's iPhone Mirroring app, and does not promise silent unlock or unattended access. Protected screens may refuse capture or hide content.

References: [Android AccessibilityService](https://developer.android.com/reference/android/accessibilityservice/AccessibilityService), [accessibility keyboard connection](https://developer.android.com/reference/android/accessibilityservice/InputMethod.AccessibilityInputConnection), [Android Bluetooth transfer](https://developer.android.com/develop/connectivity/bluetooth/transfer-data), [Apple RFCOMM](https://developer.apple.com/documentation/iobluetooth/iobluetoothrfcommchannel).
