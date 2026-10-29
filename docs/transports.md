# Transport options and platform requirements

Status reviewed: **27 October 2026**. This guide separates shipped Twinvia behavior, earlier feasibility observations, and designs that would need a new implementation. It is not a list of transport switches available in the app.

Twinvia 0.9.0 ships **Bluetooth LE through Google Nearby Connections**, with certificate-pinned TLS and QR-derived application authentication. It does not ship Wi-Fi Aware, AWDL, Wi-Fi Direct, LAN, hotspot, USB-data, or cloud-relay adapters. Its Mac helper disables the SDK's Wi-Fi transport upgrades. Earlier experiments do not describe the current release.

The product requirement is nearby Android–Mac communication while the Mac keeps its existing network connection, without relying on a common access point, enterprise inter-VLAN routing, or a cloud service. Sharing an SSID does not establish reachability: client isolation, firewalls, VLANs, and discovery filtering can still block application traffic. LAN and hotspot are included below for comparison; neither satisfies that requirement reliably.

## Terms that must not be confused

- **Wi-Fi Aware / NAN:** standards-based nearby discovery and data paths without an access point. Android exposes `WifiAwareManager` on compatible hardware. Wi-Fi Aware is designed to coexist with an infrastructure connection, but availability and radio concurrency still depend on the devices and firmware. See [Android Wi-Fi Aware](https://developer.android.com/develop/connectivity/wifi/wifi-aware) and [Apple's introduction](https://developer.apple.com/videos/play/wwdc2025/228/).
- **AWDL / Apple peer-to-peer Wi-Fi:** Apple's separate peer-to-peer mechanism. Apple documents its networking-API use between Apple devices; that does not provide Android with a public AWDL API or make the over-the-air protocol a supported third-party contract. See [Apple TN3111](https://developer.apple.com/documentation/technotes/tn3111-ios-wifi-api-overview).
- **Wi-Fi Direct / P2P:** another technology, exposed on Android through `WifiP2pManager`, with group negotiation and a group owner. It is not interchangeable with NAN or AWDL. See [Android Wi-Fi Direct](https://developer.android.com/develop/connectivity/wifi/wifip2p).
- **`wifip2pd`:** a macOS system-service/process name, not a public cross-platform API. Its existence or name does not establish which radio protocol a particular connection uses. The earlier native Twinvia feasibility path was NAN, not an Android implementation of AWDL.
- **Nearby Connections:** an SDK that can select multiple underlying media. Using it does not prove that a Wi-Fi upgrade occurred. This preview explicitly selects BLE; the SDK's general bandwidth claims do not describe this configuration. See [Google's overview](https://developers.google.com/nearby/connections/overview).

## Comparison

| Method | Twinvia status | What is needed | Benefits and costs |
| --- | --- | --- | --- |
| Nearby Connections over BLE | Shipped and device-tested | Google Play services on Android, ordinary Bluetooth/Nearby permissions, packaged Mac SDK helper, saved pairing | No shared LAN or network switch; adequate for events and text. Low throughput makes images and large files slow. SDK dependency and reconnect delays remain. |
| Bluetooth Classic/RFCOMM screen lane | Source prototype; hardware validation pending | Paired Bluetooth devices, ordinary Bluetooth permission, an active viewing lease and a fresh key from the pinned BLE session | Keeps image traffic separate from BLE commands without LAN/hotspot; throughput, coexistence and power use are unmeasured. See [screen setup](remote-control.md). |
| Direct BLE using GATT or L2CAP | Possible alternative; not implemented | Native Bluetooth adapters on both platforms, supported channel APIs, discovery, fragmentation, flow control, reconnect and security implementation | Could remove the Nearby dependency. More platform-specific code and compatibility testing; no measured speed or battery advantage is established. |
| Wi-Fi Aware / NAN through public APIs | Desired future wireless path; blocked by the Mac support boundary discussed below | Compatible radios and OS APIs, permissions/entitlements, discovery, authenticated data-path setup and IP sockets | Potentially better for large files while retaining the existing Wi-Fi connection. Hardware/firmware concurrency and lifecycle handling still need validation. |
| Private Mac Wi-Fi Aware path involving `wifip2pd` | Earlier lab feasibility only; excluded from release | Private service access plus system-policy authorization, compatible Android Aware implementation, network/interface handling | Earlier connectivity observations showed feasibility on the particular lab configuration. They did not establish a supported, normally installable Mac product. |
| AWDL | No Twinvia Android–Mac adapter | A supported cross-platform endpoint, or substantial low-level Android/vendor integration; neither is provided by this APK | Attractive topology for nearby Wi-Fi. Standard Android application permissions and an Apple signing certificate do not supply the missing implementation or access contract. |
| Wi-Fi Direct | Not implemented or validated as a Mac adapter | Android P2P support and a compatible, supported Mac endpoint; peer/group/routing management | No external router is needed. Mac interoperability and concurrent use of existing Wi-Fi require proof; it is not a drop-in NAN substitute. |
| Existing LAN, optionally discovered by Bonjour/mDNS | Deliberately not the default | Actual IP reachability, permitted ports and discovery, local-network consent where applicable | Ordinary IP sockets and potentially good throughput. Enterprise policy, different subnets and AP isolation can prevent use even on the same SSID. |
| Phone hotspot / SoftAP | Not implemented | User-enabled hotspot, credentials and Mac association, or another independently usable network interface | Ordinary TCP/IP and potentially useful file-transfer speeds. Can displace the Mac's current Wi-Fi connection; cellular/internet routing, power and policy need attention. |
| USB data transport | Not implemented; current USB use activates the clipboard helper only | Cable and compatible USB roles; an implemented accessory/host protocol, or explicitly authorized ADB forwarding for development | Independent of wireless congestion and LAN isolation; potentially stable throughput. Requires a cable, consent and additional endpoint/lifecycle work. ADB is a development dependency, not an invisible consumer permission. |
| Internet relay | Not implemented | Reachable service, accounts/device trust, end-to-end encryption, operation and abuse controls | Can work across different networks. Requires internet and server operation; adds metadata exposure, cost and latency. It does not meet the offline requirement. |

These are qualitative trade-offs, not comparative benchmarks. A higher-rate Wi-Fi link may finish a transfer sooner while drawing more instantaneous radio power; that does not determine energy per transfer. Likewise, persistent BLE discovery can cost more than an idle connected link. Unplugged battery tests are required before ranking methods by efficiency. The short powered-device samples in [BLE observations](ble-transport.md#observed-limits) are not battery measurements.

## What each method requires

### Current BLE path

Android requires the manifest/runtime permissions appropriate to the target SDK and Nearby API. This app checks Bluetooth scan, connect, advertise, and Nearby Wi-Fi permission before discovery; the latter does not enable a Wi-Fi data adapter. The Mac requires ordinary Bluetooth consent and the bundled helper. No restricted Wi-Fi entitlement, administrator service, SIP change, or custom boot configuration is part of the release. See [Google's permission guide](https://developers.google.com/nearby/connections/android/get-started) and the checked-in Android manifest for the exact current application configuration.

The app additionally requires its own QR/pin authentication. A device being nearby or accepted by the SDK is not sufficient authorization for notification or clipboard content. Read the [BLE security layers](ble-transport.md#authentication-layers).

### A future supported Wi-Fi Aware path

On Android, first check `FEATURE_WIFI_AWARE` and current service availability, not just the OS version. Add the Wi-Fi/network manifest permissions and runtime Nearby Wi-Fi permission appropriate to the target SDK. Create discovery sessions, obtain an authenticated data path, and use its scoped network/address information for sockets. Handle availability loss and recreate sessions. Wi-Fi Direct, tethering, or SoftAP can constrain coexistence on some devices. [Android's setup and availability documentation](https://developer.android.com/develop/connectivity/wifi/wifi-aware) describes these requirements.

On a **supported Apple platform**, Apple's public framework requires the `com.apple.developer.wifi-aware` entitlement with the intended `Publish`/`Subscribe` roles, corresponding `WiFiAwareServices` declarations, and runtime hardware/feature support. These requirements are additional to normal signing; they do not establish Mac support. See the [entitlement reference](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.wifi-aware) and [service declarations](https://developer.apple.com/documentation/bundleresources/information-property-list/wifiawareservices).

For Twinvia, a viable Mac implementation needs Apple-supported native macOS discovery, pairing and IP-data-path APIs, an actual entitlement/provisioning path when required, compatible hardware, and a clean-system interoperability test with Android. A checkbox in the developer portal, a framework in an SDK, or an available system daemon does not satisfy these conditions.

### What using `wifip2pd` would mean today

The system daemon is not something an application installs or starts to acquire a public transport. Earlier local work used private Mac facilities and a nonstandard lab security configuration. That demonstrated a particular NAN data path; it did not create an entitlement Apple authorizes for arbitrary developers.

A design based on that route would have to solve all of the following:

1. Obtain a supported and authorized Mac service/API contract. Client-policy checks and entitlement/code-signing checks are separate requirements; a Developer ID certificate alone does not grant them.
2. Match Android Aware discovery and data-path credentials, then establish and authenticate the actual IP channel.
3. Correctly manage scoped IPv6 endpoints, interface lifetimes, addressing, reconnects and sleep/wake. A discovery callback alone does not establish a usable stream.
4. Work under default system protections and survive OS updates without private-framework assumptions or administrator-assisted network workarounds.

The release has no implementation meeting that contract. Its build does not ship the earlier private helpers or apply OS-policy changes. Disabling security checks would not turn a private interface into a supported distribution path. This guide intentionally contains no research bypass commands, patches, hashes, captures, or private diagnostic reports.

### AWDL, system sharing, and Apple-only APIs

An OS-managed Quick Share/AirDrop transfer is different from Twinvia holding a persistent application socket. A successful system-share observation on a particular Samsung/Mac combination does not grant a third-party APK access to the system sharing implementation or prove a reusable Android AWDL API. Similarly, enabling an Apple peer-to-peer networking option in a Mac API does not implement the other endpoint on Android. Apple's [peer-to-peer API guidance](https://developer.apple.com/documentation/technotes/tn3111-ios-wifi-api-overview) describes the platform boundary.

Do not infer AWDL support from an advertising event, Bluetooth pairing, or the presence of `awdl0`. Any proposed adapter must prove the actual data interface, bidirectional authenticated payloads, reconnect behavior and normal-user installation. No such adapter is included here.

### USB and hotspot are separate designs

Current clipboard-helper activation over ADB does not route Twinvia application traffic over USB. An ADB-forwarded socket would need a new adapter and explicit USB-debugging authorization. A consumer USB accessory design is another option with distinct hardware-role, permission and enumeration requirements; see [Android USB accessory support](https://developer.android.com/develop/connectivity/usb/accessory). Neither is implemented by plugging in the current APK.

A phone hotspot provides infrastructure IP connectivity after the Mac joins it. It is not a way to invoke AWDL/NAN. Keeping another Wi-Fi association concurrently depends on available interfaces and hardware support; Twinvia must not promise this on the user's existing adapter. This is why a hotspot is not the selected solution for preserving the Mac's current network.

## What changes in the application

| Concern | What a new adapter changes | What it does not automatically solve |
| --- | --- | --- |
| Notifications and phone controls | Discovery, connection setup, failure handling and delivery latency | Android notification access, filtering, replay suppression, actions, contacts and call-log permissions |
| Text/image clipboard | Available bandwidth and timeouts; images may become practical on a faster link | Android background clipboard restrictions, the helper's authorization, lock-state privacy, echo prevention |
| File transfer | Throughput, chunk sizing, backpressure and retry behavior | User approval, storage permissions, path validation, SHA-256 verification, cancellation; queues/resume still need implementation |
| Calls | A faster link could carry a suitably authorized future audio stream | Cellular-call audio capture/routing, HFP interoperability, microphone consent, or registration of an Android line in Apple's Phone/Messages apps |
| Security and lifecycle | Interface-scoped admission, radio/network permissions, connection deadlines, reconnection strategy and migration tests | Saved device trust, certificate pinning, application authentication, payload limits and bounded queues must remain |

Changing transport is not an Android permission escalation. In particular, `AudioPlaybackCapture` is constrained by eligible audio usages and capture policy; it does not provide a general cellular-call relay. Android documents `CAPTURE_AUDIO_OUTPUT` as unavailable to ordinary third-party applications. See [playback capture constraints](https://developer.android.com/media/platform/av-capture) and the [permission reference](https://developer.android.com/reference/android/Manifest.permission#CAPTURE_AUDIO_OUTPUT). Better Wi-Fi bandwidth alone cannot fix the preview's call-audio limitation.

Implementation work should stay behind the existing `PeerLink` boundary, preserve the application protocol and saved trust, and test fresh pairing, old-pair reconnection, lock/unlock, radio loss, sleep/wake, denied permissions and bounded memory use. Switching an adapter must not silently erase keys or fall back to an unrelated network. Any measured throughput or power claim must name the devices, OS versions, transport and test duration.

## Discussion and feedback submitted to Apple

This requirement was raised in [Apple Developer Forums thread 853064](https://developer.apple.com/forums/thread/853064?answerId=911932022#911932022). The DTS response reviewed on **26 October 2026** confirmed that Wi-Fi Aware was unsupported on macOS at that time: enabling the capability did not cause Mac development or Developer ID profiles to include the entitlement. The recommended alternatives included hotspot, BLE and USB. An independent [Apple DTS explanation of Mac support](https://developer.apple.com/forums/thread/827887) also distinguishes framework presence/Mac Catalyst availability from working device support.

Following that discussion, two feedback reports were submitted on **26 October 2026**: an enhancement request for public macOS Wi-Fi Aware discovery/pairing/IP paths with Android interoperability, and a developer-portal clarification request about the misleading provisioning-support presentation. A follow-up was submitted to the [same forum thread](https://developer.apple.com/forums/thread/853064?page=1#911963022); its visibility may depend on forum moderation. Private Feedback Assistant report contents and diagnostics are not included in this repository.

The requested result is an authorized, distributable Mac app operating with standard system protections while keeping the existing infrastructure connection. Filing feedback or accepting a forum answer does not grant an entitlement, promise delivery, or establish a release date. The dated discussion and saved submission record establish this support-status record; a later private-feedback resolution has not been verified. Recheck Apple's documentation, runtime feature support and actual provisioning before describing a future macOS version as supported.
