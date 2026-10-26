# BLE transport

## Supported path

Android uses Google Play services Nearby Connections; the Mac helper builds the public Google Nearby source pinned by `scripts/prepare-nearby-sdk.py`. Discovery advertises an invitation-specific service/context. Application traffic uses BLE only: the Mac SDK configuration disables upgrades to LAN, hotspot, Wi-Fi Direct, NAN, and AWDL. A shared network is not required.

The helper is packaged at `Twinvia.app/Contents/Resources/AndrofestBluetooth.app`. It has ordinary Bluetooth permission and no restricted entitlements. The build neither installs an administrator helper nor changes system-security settings. Code-signing certificates identify the application; they do not grant unrestricted access to system services.

## Authentication layers

1. The QR carries an invitation ID, device ID, expiry, and random 32-byte secret. It expires after five minutes for a new association; existing saved trust remains usable after that expiry.
2. HMAC-SHA-256 with separate domains derives the discovery service and role-specific endpoint context. These reduce unsolicited matching; seeing or connecting to a service does not authorize application data.
3. A compact phone introduction authenticates its identity and TLS certificate fingerprint with HMAC, nonce, and time validation. The Mac compares saved identity/pin for reconnection.
4. The Mac opens TLS through the byte relay and pins the phone certificate. Inside TLS, Android verifies `session.auth` against pending or saved invitation trust. Only then can `device.hello` establish application state and saved trust.

Mac trust is stored in Keychain. Android encrypts saved invitation material with a Keystore AES-GCM key. Keychain denial is an explicit UI state; it is not treated as permission to erase trust or issue a replacement QR. No pairing secrets or clipboard content belong in diagnostic logs.

## Framing and backpressure

TLS application frames use a four-byte big-endian length with the shared codec's maximum size. Invalid lengths are rejected before allocation. The byte tunnel has separate introduction, sequenced data, and acknowledgement packets. Data fragments are at most 8 KiB; each direction permits one outstanding fragment and a bounded receive queue. The receiver acknowledges only after writing to its local TCP stream. Missing or unexpected acknowledgements close the tunnel rather than growing queues indefinitely.

Android's TLS listener binds loopback. Admission additionally checks the exact source port registered by the app-owned tunnel. The Mac helper exposes a loopback relay; TLS and QR-secret authentication remain necessary even for a local connection. Nearby does not replace application trust.

The helper validates endpoint context and bounds connection attempts. Tunnel and TLS setup have deadlines. Link failure closes the session, preserves saved trust, and retries with bounded backoff. Android stops discovery once connected; idle heartbeats run every 30 seconds, with a 120-second application watchdog. Radio/SDK delays can make recovery slower than the backoff itself.

## Dependency provenance

The reviewed product patch is in [vendor/nearby](../vendor/nearby/README.md). It provides transport-upgrade flag configuration and fixes BLE service registration when CoreBluetooth has not yet reported a powered state. No OS/framework binary is patched. The original SDK and its transitive dependencies retain their upstream licenses.

## Observed limits

A device trial transferred a 116,608-byte PNG in about 18 seconds and verified a 64 KiB file round trip. Normal application reopen recovered in about 12 seconds, an Android Bluetooth off/on cycle in about 38 seconds, and forced helper termination in about 66 seconds. These individual observations are not performance guarantees.

A short background sample observed about 3.33% of one Mac CPU core, 154.17 MiB summed Mac RSS, and 75.49 MiB Android PSS. A separate 30-second Android application CPU-time sample was about 2.71% of one core; it excludes shared Play services and the separate clipboard helper. RSS can double-count shared pages. The powered phone and short intervals do not establish battery drain, long-term stability, or comparative transport efficiency.

Real-device and clean-host validation remain separate from unit tests. See [testing](testing.md).
