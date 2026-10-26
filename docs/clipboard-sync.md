# Clipboard synchronization

## Behavior

Copy text or URLs on either device and paste on the other. Mac PNG/TIFF screenshots can populate the Android image clipboard. Android-to-Mac image clipboard and clipboard file lists are not implemented. The source clipboard is not cleared after transfer.

Android background clipboard reading is restricted by the OS. Accessibility or device-administrator permission alone is not the supported background-read mechanism here. Twinvia uses an **optional shell-identity helper**, activated with ADB on a device you control. This helper is more privileged than the normal application and should be enabled deliberately.

## Activate

1. Install the APK and pair it with the Mac.
2. Unlock the phone, enable USB debugging, connect USB, and authorize the development computer.
3. Run `python3 scripts/enable-clipboard.py` from the repository root. With several devices connected, add `--serial DEVICE_SERIAL`.
4. Check that automatic clipboard is enabled and the phone reports the helper ready. Copy and paste normally.

The activation script builds/pushes the helper and starts it under the ADB shell identity. No APK UID is changed and no root or system-policy modification is required. USB is not the application transport. After a phone reboot, activate again. An ordinary bridge reconnect should not require repeating activation.

## Privacy and failure handling

- The helper authenticates to an app-owned loopback endpoint using a challenge/response secret in app-private configuration. It is not a network clipboard server.
- Clipboard sharing pauses while the phone is locked or the bridge is disconnected. Reconnection refreshes the helper session to recover stale listeners.
- Text has size limits and echo suppression. Only the latest pending clipboard update is tracked by the Mac controller.
- An image is assembled with chunk bounds and SHA-256 validation before application. Completion waits for the phone acknowledgement. BLE-aware deadlines avoid reporting a timeout before a normal image transfer can finish.
- Diagnostics contain counters/state, not clipboard contents. Test fixtures are synthetic; the test utility holds the original Mac clipboard in RAM and only restores it if the user has not copied something else.

To disable sharing, turn off automatic clipboard synchronization in the app. This stops sharing; the already activated helper process may remain waiting locally until phone restart. Disconnect USB and turn off USB debugging when it is no longer needed.

See [device tests](testing.md) for the repeatable text/image checks.
