# Phone mirroring and control

This source-build prototype provides a dedicated, resizable SwiftUI phone window. Open **Screen → Open phone mirror**, the tray's **Phone mirror** button, or `twinvia://screen`. The window follows explicit opens to the current macOS Space and supports normal resizing/full screen. Closing it stops the screen lane and clears the image; minimizing pauses preview requests. Mac sleep closes the screen lane and clears the image; capture requires an explicit refresh after waking. The companion bridge remains available independently of the mirror window.

## Phone approval

1. Enable **Twinvia screen control** in Android Accessibility settings. The service declares screenshot, gesture and input-method capabilities. It does not read accessibility event contents, surrounding text or the UI tree.
2. On the phone, select **Start screen viewing** and approve its disclosure. A persistent notification offers **Stop sharing**. The lease lasts at most five minutes; lock/screen off, connection loss, service revocation or app-process exit ends it.
3. Approve **Enable touch control** separately to permit taps, swipes, keyboard input and navigation. Remote requests cannot start or extend either approval.
4. In the Mac mirror, refresh the screen. Click to tap, drag to swipe, or use Back/Home/Notifications. The keyboard button sends explicitly entered text (at most 1,024 UTF-16 units), Enter or Backspace to the focused phone editor through Android's public accessibility input connection. Some editors/OS versions may refuse input. Text is not logged or added to clipboard history.

## Image quality and preview

**Responsive** keeps the earlier 480-pixel long-edge JPEG path (at most 70,000 encoded bytes). **Detail** captures up to a 2,160-pixel long edge and compresses to at most 130,000 bytes. Wire metadata is limited to 2,560 pixels per edge and 4,194,304 total pixels. The Mac checks the actual JPEG dimensions against that metadata before decoding. Screen images remain in memory and are never saved by Twinvia. A stale displayed frame expires after 30 seconds; lock/session-state updates also clear it and disable input. New APKs report viewing and input approval separately.

Detail requires the `remote.screen.v2` capability. Older paired APKs keep the original screenshot path. BLE detail transfers can be slow; increasing JPEG resolution cannot create more radio bandwidth. The play/pause button requests the next image only after the prior response and a short delay, keeping at most one image in flight. This is a screenshot preview, not a MediaProjection/H.264 live-video implementation or a claimed 30/60 FPS stream.

## Wi-Fi screen lane

In **Screen connection → Connect Wi-Fi screen**, opt in to a separate local-network image channel. The phone and Mac must be able to reach each other on an existing local network. Twinvia does not switch networks, start a hotspot, or send screen content through a cloud service. The normal authenticated BLE bridge continues to carry commands and pairing; losing that bridge ends screen access. Older APKs without `remote.screen.lan` keep the original path.

The phone binds an ephemeral listener to one RFC1918 IPv4 Wi-Fi address. It accepts one client, stops listening after that accept, and closes an unused listener after 15 seconds. A fresh 256-bit screen key and session ID arrive only through the pinned BLE connection. Both network directions use the same bounded AES-256-GCM record protocol and strict counters as the Classic lane. This is application-layer authenticated encryption over TCP, not a claim that the socket itself uses TLS. A client must authenticate its first request within five seconds. A network socket idle for 30 seconds closes; pause, lock, consent expiry and disconnect also close it. Public/DNS/loopback endpoints and invalid ports are rejected by both protocol implementations.

Client isolation, firewalls or denied macOS Local Network permission can prevent access even when Wi-Fi names match. The app reports a failure. Choose **Use Bluetooth LE** to explicitly return to the slower path; no shared-network availability is promised on corporate/guest networks. Android currently targets SDK 36; moving to SDK 37 requires the Android local-network runtime permission flow as well.

## View controls and privacy

Use **View scale → Fit / 150% / 200%** to inspect sharper text. At Fit, drag gestures, trackpad/wheel input and the visible up/down controls scroll the phone. When zoomed, dragging pans the local image; the arrow controls still scroll the phone. Keyboard input and all phone gestures continue to require separate phone-side approval.

**Privacy break** pauses this Mac's clipboard, mirrored notifications and screen/input requests for 5, 15 or 60 minutes. Its deadline survives an app restart, and wake checks expiry. Paused clipboard changes and notifications are dropped rather than replayed on resume. Existing mirrored notifications and the current image are removed; already-transmitted data cannot be recalled. Calls and explicit file transfers remain available. Resuming does not silently restart the mirror; request a fresh frame and reconnect the screen lane if needed.

## Optional faster Bluetooth lane — experimental

The bolt button opens a separate Bluetooth Classic/RFCOMM screenshot lane. Pair the phone through macOS Bluetooth settings, choose it in the mirror popup, and connect while the phone-approved viewing lease and existing BLE session are active. This uses public Android BluetoothSocket and Mac IOBluetooth APIs; it does not require a shared LAN, hotspot, USB debugging, SIP changes or private Wi-Fi APIs.

The existing certificate-pinned connection issues a fresh random 256-bit screen key and session ID. Only screen requests/responses use RFCOMM; phone controls remain on the existing connection, so an RFCOMM image does not fill the BLE application stream. The screen channel uses AES-256-GCM, distinct per-direction nonces, a session-bound authenticated context, strict monotonic counters and bounded frames. Replay, reflection, tampering and out-of-order records are rejected. A listener accepts one socket; unauthenticated sockets close after five seconds, discovery expires after fifteen seconds, and the normal phone lease bounds the whole session. The selected paired device still needs the application key before it can receive any screen image.

On screen-lane loss the preview pauses and the displayed image clears. The authenticated BLE pairing remains; the user may refresh over BLE or reconnect the faster lane. A failed experiment does not remove pairing or silently switch to a LAN.

**Validation limit:** the Android and Mac implementation, protocol interoperability vectors, tamper/replay tests, bounds and builds can be checked without a phone. RFCOMM reachability, actual throughput, coexistence with BLE/HFP, vendor input behavior and battery use require the physical phone. Device measurements must name the transport and distinguish JPEG response latency from video FPS. Bluetooth Classic may still be insufficient for high-quality live video; a separately supported faster transport and Android MediaProjection/MediaCodec would be needed for that product goal.

This is Twinvia's own interface. It does not register Android as an iPhone in Apple's iPhone Mirroring app, and does not promise silent unlock or unattended access. Protected screens may refuse capture or hide content.

References: [Android AccessibilityService](https://developer.android.com/reference/android/accessibilityservice/AccessibilityService), [accessibility keyboard connection](https://developer.android.com/reference/android/accessibilityservice/InputMethod.AccessibilityInputConnection), [Android Bluetooth transfer](https://developer.android.com/develop/connectivity/bluetooth/transfer-data), [Apple RFCOMM](https://developer.apple.com/documentation/iobluetooth/iobluetoothrfcommchannel).
