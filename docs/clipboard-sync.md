# Clipboard synchronization

## Behavior

Copy text or URLs on either device and paste on the other. Mac PNG/TIFF screenshots can populate the Android image clipboard. Android-to-Mac image clipboard and clipboard file lists are not implemented. The source clipboard is not cleared after transfer.

Android background clipboard reading is restricted by the OS. Accessibility or device-administrator permission alone is not the supported background-read mechanism here. Twinvia uses an **optional shell-identity helper**, activated with ADB on a device you control. This helper is more privileged than the normal application and should be enabled deliberately.

## Activate

1. Install the APK and pair it with the Mac.
2. Unlock the phone, enable USB debugging, connect USB, and authorize the development computer.
3. Run `python3 scripts/enable-clipboard.py` from the repository root. With several devices connected, add `--serial DEVICE_SERIAL`.
4. Check that automatic clipboard is enabled and the phone reports the helper ready. Copy and paste normally.

The repository activation script builds the helper when needed, then pushes/starts it under the ADB shell identity. The release helper kit includes a prebuilt JAR: run its `enable-clipboard.py` without a build toolchain, with `--adb /path/to/adb` when necessary. No APK UID is changed and no root or system-policy modification is required. USB is not the application transport. After a phone reboot, activate again. An ordinary bridge reconnect should not require repeating activation.

## Privacy and failure handling

- The helper authenticates to an app-owned loopback endpoint using a challenge/response secret in app-private configuration. It is not a network clipboard server.
- Clipboard sharing pauses while the phone is locked or the bridge is disconnected. Reconnection refreshes the helper session to recover stale listeners.
- Text has size limits and echo suppression. Only the latest pending clipboard update is tracked by the Mac controller.
- An image is assembled with chunk bounds and SHA-256 validation before application. Completion waits for the phone acknowledgement. BLE-aware deadlines avoid reporting a timeout before a normal image transfer can finish.
- Diagnostics contain counters/state, not clipboard contents. Test fixtures are synthetic; the test utility holds the original Mac clipboard in RAM and only restores it if the user has not copied something else.

To disable sharing, turn off automatic clipboard synchronization in the app. This stops sharing; the already activated helper process may remain waiting locally until phone restart. Disconnect USB and turn off USB debugging when it is no longer needed.

See [device tests](testing.md) for the repeatable text/image checks.

## Improvement options

Android clipboard authorization and device-to-device delivery are separate problems. A faster Wi-Fi link changes delivery performance; it does not give an ordinary background APK access to the clipboard. Android documents access for the app that currently has focus or the default input method editor (IME). Merely running a foreground service does not give its UI focus. See [Android's clipboard access rule](https://developer.android.com/about/versions/10/privacy/changes#clipboard-data).

The current preview routes clipboard reads and writes through the authenticated shell helper. Reading a copy made inside another Android app is the difficult authorization case. Receiving a Mac update, publishing an image URI with correct grants and applying it to Android are separate operations; future adapters should validate each direction instead of treating one successful test as full support.

| Option | Experience | Setup and limitations | Planning status |
| --- | --- | --- | --- |
| Improve the existing helper | Fully automatic text synchronization while the helper is alive and the phone is unlocked/connected | Explicit USB-debugging authorization for activation; repeat after reboot. A normal reconnect reuses the running helper. OS/private Binder compatibility still needs testing. | Preferred first improvement; current mechanism is already device-tested |
| Optional Shizuku adapter | Potential shell-backed clipboard access managed through Shizuku, with a permission grant to Twinvia | Extra trusted app and user authorization; non-root startup uses ADB/wireless debugging and normally repeats after reboot. Not a permanent public clipboard entitlement. | Prototype required on the current Samsung/Android version |
| Explicit share/focused-app mode | Share selected text/images to Twinvia, or open/focus Twinvia and choose what to send | Can avoid a privileged helper; requires user interaction and source-app support. Does not meet the automatic cross-app copy goal. | Useful optional fallback; no claim of a complete fallback workflow in this preview |
| Default IME / companion keyboard | Could use the documented default-IME access path | User must deliberately select a Twinvia keyboard; substantial input, privacy, language and keyboard-feature work. A transient keyboard switch is not a zero-setup solution. | Exploratory; not the preferred default |
| OEM/system integration | Could provide platform-authorized background access with an appropriate vendor integration | Manufacturer/system privileges and a supported deployment contract; unavailable by simply signing an ordinary APK | Platform/vendor dependency |

[Shizuku's official setup guide](https://shizuku.rikka.app/guide/setup/) describes its root/non-root startup and reboot constraints. Wireless setup availability is device/network dependent; it must not be presented as guaranteed offline, once-only setup. A Twinvia Shizuku adapter would still need app-specific permission handling, revocation, service-death recovery and actual clipboard interoperability tests. It is not currently bundled or implemented.

Accessibility services may help implement separately authorized remote input, but accessibility permission alone is not the documented global clipboard-read path. Ordinary device-administrator enrollment likewise must not be offered as a universal clipboard permission. A fake focus window would interrupt the active app and is not an acceptable automatic-sync design.

The proposed next step is a guided setup and health screen around the existing helper, followed by an optional Shizuku feasibility test. Keep a narrow adapter contract so both mechanisms use the same authenticated bridge, lock-state checks, echo suppression and acknowledgements. Do not make root access, device-owner reprovisioning, a custom keyboard, or screen scraping prerequisites for normal Twinvia use.

## Format, privacy, and recovery work still needed

- Add per-direction sharing controls, a temporary pause and clear send/apply/blocked states. A UI must distinguish helper authorization, phone lock and radio/session failure.
- Prototype Android-to-Mac images using bounded URI reads, MIME validation, expiry and integrity checks. The current helper only emits text changes; the reverse image direction is not implemented.
- Define simultaneous-copy and reconnect behavior explicitly. Current watchers baseline clipboard state when disabled/disconnected or reconfigured; they do not intentionally replay historical copies after reconnect. An explicit resend action is preferable to silently uploading an old clipboard.
- Preserve existing Android sensitive-clip filtering and Mac concealed-type filtering; improve user controls without claiming every secret can be detected. Source applications may omit sensitivity markers. See [Android clipboard security guidance](https://developer.android.com/privacy-and-security/risks/secure-clipboard-handling).
- If clipboard history is added, make retention optional, bounded, protected at rest where stored, and easy to clear. Clipboard diagnostics remain content-free.
- Test helper death, permission revocation, phone reboot, process replacement, lock/unlock, rapid copies and image cancellation on the supported OS/vendor matrix. An APK-only, zero-setup, permanently automatic solution across arbitrary Android apps is not established by these options.

See the [product roadmap](roadmap.md) for prioritization. These improvement options are proposals, not new features in the released APK.
