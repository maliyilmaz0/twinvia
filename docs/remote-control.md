# Phone screen viewing and control

This source-build prototype uses the existing paired, certificate-pinned connection. It sends one compressed screen image when requested. It does not continuously stream video. Bluetooth LE bandwidth makes rapid screen interaction impractical; the Mac updates the image after each completed action.

## Set up

1. Install current source builds on both devices and connect the saved pairing.
2. On the phone, open Twinvia → Device → Screen control → **Open Accessibility settings** and enable **Twinvia screen control**. This service declares screenshot and gesture capabilities. It does not read accessibility event contents or the UI tree.
3. Return to Twinvia and select **Start screen viewing**. Read and approve the separate disclosure. A visible phone notification has **Stop sharing**. The session lasts at most five minutes and ends on disconnect, screen off/lock, service revocation, or app-process exit.
4. On the Mac, open **Screen** and select **Refresh screen**. Screen images remain in memory and are not saved by Twinvia.
5. To send taps, swipes, Back, Home, or open the notification panel, select **Enable touch control** on the phone and approve its second disclosure. Click or drag on the image on the Mac, or use the Back/Home/Notifications buttons. A refresh follows each accepted action.

The phone can stop the session from the app or its notification. A remote command cannot start or extend a session. The authenticated peer and current phone-side lease are checked for every command. Touch coordinates are bounded to the screen; commands are rejected while the phone is locked. Protected screens may refuse capture or hide content.

## Limits and privacy

- The JPEG is scaled to at most 480 pixels in either dimension and capped at 70 KiB. The Mac reports the received size and elapsed time after each refresh. Exact behavior and latency depend on screen content and BLE conditions.
- Tap, swipe, Back, Home and opening the notification panel are exposed after input approval. There is no keyboard entry, unattended access, unlock, or settings bypass.
- Android's AccessibilityService permission is powerful. Enable it only if you intend to use this feature; disable it in Settings at any time. If this feature is distributed through Google Play, its accessibility declaration, prominent in-app disclosure and consent must be reviewed against the current policy.
- This remains a source-build prototype. Validate latency, input, permissions and protected-screen behavior on each supported OS/vendor combination before calling it a release feature.

The platform APIs are documented by [Android AccessibilityService](https://developer.android.com/reference/android/accessibilityservice/AccessibilityService) and [service configuration](https://developer.android.com/guide/topics/ui/accessibility/service). See [test strategy](testing.md) and [roadmap](roadmap.md).
