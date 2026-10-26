# Wire contract

Both applications implement the same envelope, pairing, file, image, and BLE byte-pipe contracts. `envelope.schema.json` describes JSON payload shapes; synthetic shared fixtures in `fixtures/` are validated in Kotlin and Swift. Fixed keys and identities in those fixtures are test data, never installation credentials.

## Application stream

Application traffic runs inside certificate-pinned TLS. `WireFrame` encodes a four-byte network-order payload length followed by payload bytes. Empty and oversized frames are rejected before allocation. JSON control envelopes use version 1, UUID `id` and `sourceDeviceId`, a positive epoch-millisecond `timestamp`, and a validated `type`/`payload`. Unknown fields are tolerated for compatibility; unknown types/versions and missing required fields are rejected.

Envelope types include `device.hello`, notification posted/removed, file offer/accept/complete/cancel, `device.command`, `command.result`, `device.status`, and `text.shared`. Binary file (`AFC1`), clipboard image (`ACI1`), and legacy audio (`AAP1`) payloads have independent codecs and bounds. Audio capability is not advertised over BLE.

## Pairing and discovery

New pairing uses an address-free version-2 five-minute QR invitation. Saved version-1 records remain readable for identity/key compatibility; their old network destination is not used by BLE. The compact introduction retains the `AFN1` byte format: UUID, TLS port, SHA-256 certificate fingerprint, nonce, timestamp, bounded UTF-8 name, and HMAC proof. Changing its source type name must not change serialized bytes or saved trust identifiers.

`NearbyBleProtocol` derives a service ID and separate Mac/phone contexts using domain-separated HMAC-SHA-256. Packet kind 1 carries the compact introduction; kind 2 carries a uint32 sequence plus 1–8192 ciphertext bytes; kind 3 acknowledges that sequence. Sequence validation and bounded flow control belong to tunnel adapters. TLS and session authentication remain required after transport matching.

## Commands and notifications

Only explicitly supported device actions are decoded. Tokenized notification/call actions require current state and permission checks. A bounded command-result history suppresses repeated completed effects; reads and sensitive state-dependent commands are checked again. Stale/future timestamps fail before cached results are returned. This is not exactly-once delivery across restarts.

`notification.posted.isReplay=true` identifies an existing notification snapshot. It can update state without a new banner or sound. Content-level notification deduplication is distinct from envelope-ID replay suppression.

## Files and images

File transfers require receiver approval, validate offsets and chunk sizes, and verify total length and SHA-256. The 2 GiB protocol limit is not a BLE throughput guarantee. Images are bounded separately and acknowledged after application. Keep resource limits synchronized across both implementations.

## Changes

Update the schema, shared fixtures, both implementations, and tests together. Preserve compatibility or explicitly introduce a version migration. Run the Swift and Kotlin protocol suites; never regenerate expected vectors with the implementation under test and call that independent verification. See [architecture](../../docs/architecture.md) and [testing](../../docs/testing.md).
