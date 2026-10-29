# Test strategy

## Automated checks

Run `./scripts/check.sh`, `./scripts/test.sh --console=plain`, and both platform build scripts from the root. Unit tests run without a physical phone and do not send calls, notifications, or clipboard data to a production device.

| Suite | Important cases |
| --- | --- |
| Swift and Kotlin protocol | Shared fixtures, envelope validation, QR/authentication data, role-separated HMAC contexts, malformed/oversized BLE packets, file/image chunks, bounds, hashes, and wire framing. |
| Android session policy | Valid pending trust, expiry, saved trust after QR expiry, wrong identity/secret/version, and capability count/size limits. |
| Android command policy | Malformed request followed by valid work, stale/future timestamps, replaced sessions, bounded duplicate history, permission rechecks, cancellation propagation, and bounded error messages. |
| macOS application | Filesystem safety, transfer state, clipboard decisions, notification deduplication, command results, phone-data paging, certificate pins, denied Keychain startup, transport lifecycle, and replay-window bounds. |
| Publication/tooling | Product allowlist, ignored investigations, force-staged forbidden files, obvious credential material, and product dependency inclusion. |

The repository does not claim complete branch coverage, absence of all vulnerabilities, or production call-audio support. Hardware radio behavior, OS permission dialogs, sleep/Doze, HFP audio, and battery life need device tests beyond these unit suites. Keep a regression test for each fixed failure at the smallest boundary that reproduces it.

Android lint errors fail the build. Non-blocking advisories can remain for pinned dependency upgrades, optional KTX style, storage allocation APIs, and Google Play's All files access policy. They are reported without a generated lint baseline. This developer APK is not a claim of Google Play approval; dependency-major upgrades and store-policy changes require separate review.

## Device checks

Use devices you control and synthetic content. Keep the phone unlocked for clipboard tests. APKs must be signed compatibly with installed app state; never erase daily trust just to get a test passing.

### Existing pairing and clipboard

```sh
python3 scripts/test-clipboard.py --serial DEVICE_SERIAL --image
```

The separate clipboard-probe package checks actual copy/paste, Unicode, lack of echo loops, and PNG integrity. The script keeps original Mac clipboard formats in RAM, restoring them only if no new user copy replaced the fixture. Test counters/results are local ignored artifacts. The optional Android clipboard helper must already be activated.

For the APK-only Mac-to-phone path, stop the optional helper and run `python3 scripts/test-clipboard.py --serial DEVICE_SERIAL --image --without-helper`. The phone must be unlocked. This checks text and PNG from the Mac without claiming automatic Android-to-Mac reads.

### Fresh pairing isolation

Build a separate debug application with `-Ptwinvia.pairingTest=true`, copy its APK to `.artifacts/ble-integration/Twinvia-pairingtest.apk`, and use `python3 scripts/test-ble-pairing.py`. Read the script preconditions first: it refuses an existing test identity instead of erasing state. It uses a separate Android package and Mac probe, bootstraps only the test QR over USB, and checks fresh TLS trust, a synthetic notification, and saved reconnection. For another run, choose a fresh `.pairingtest` suffix with `-Ptwinvia.pairingTestSuffix=.pairingtestUNIQUE` (lowercase letters/digits) and matching `--package`/`--apk` arguments. The harness validates APK identity before stopping the daily bridge, stops the competing daily Mac advertiser, and restores it during cleanup. Daily pairing stores must remain untouched. The package is left installed and stopped after testing.

### Manual regression matrix

- Normal application quit/reopen and phone Bluetooth off/on: saved trust reconnects; text and PNG still work afterwards.
- Sleep/wake and range loss: no duplicate helper/session, no new QR required, no stale queue execution.
- Locked phone and revoked permissions: clipboard pauses; protected data reads fail and recheck permission on the next request.
- Synthetic file both ways: explicit receiver approval, matching SHA-256, cancellation, disconnect cleanup, and no traversal/symlink overwrite.
- Notifications: unchanged snapshots/reconnect do not repeat banners; real updates and removals behave correctly.
- Call controls: current-call tokens and explicit consent are honored. Do not mark Mac audio verified based on Bluetooth connection status alone.

## Resource observations

```sh
python3 scripts/measure-bridge-resources.py --label UNIQUE_LABEL --seconds 120
```

The script does not reset battery statistics or simulate unplugging. Mac CPU uses process CPU-time deltas; RSS sums may count shared pages repeatedly. Android PSS and rolling `dumpsys cpuinfo` are observational; old transfer windows can distort an idle CPU sample. Shared Play services usage cannot be attributed entirely to Twinvia. USB/power and short intervals invalidate battery-drain conclusions. Use matched, unplugged, long-duration windows before making battery-life claims.

## CI evidence

CI exports Android JUnit XML, HTML test reports, and lint reports; Mac job logs contain Swift test results. Hardware tests are deliberate local checks, not green-check substitutes. Repository configuration, local tests, real-device behavior, and a successfully run remote pipeline are separate evidence levels.

## Mirroring and signed updates

`RemoteFrameCipherTests` / `RemoteFrameCipherTest` use the same independent AES-GCM vector and exercise tampering, reflection, replay, reordering and size rejection. Mac image tests inspect real JPEG dimensions against protocol metadata. Android update tests verify Ed25519 signatures and bounded/repository-scoped metadata; Python publication tests use real OpenSSL signatures and reject a mismatched update identity. The native signing regression includes a nested Mach-O framework. These checks do not establish physical RFCOMM throughput or Android installer behavior.

Without a phone, validate compilation, signatures, protocol tests and the Mac window's disconnected state. With the phone, verify permission denial/revocation, five-minute expiry, lock/disconnect, BLE/Classic coexistence, gestures/text, memory/latency at both qualities, then a real signed APK update preserving data. Verify Mac update download, signature rejection, installation and relaunch using a controlled new signed build before publishing an upgrade claim. See [mirroring](remote-control.md) and [updates](updates.md).
