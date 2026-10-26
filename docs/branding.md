# Twinvia identity and compatibility

Twinvia is the product name starting with version 0.9.0. Its tagline is **Two devices. One flow.** The paired violet/lime paths form a compact T, with a template variant for the macOS menu bar.

## Assets

- `assets/brand/mark.svg`: editable, transparent two-color mark.
- `assets/brand/app-icon.svg`: dark-background icon artwork.
- `assets/brand/banner.svg`: repository/documentation wordmark.
- The macOS asset catalog includes native app-icon sizes and 18-point menu-bar images at 1x/2x/3x.
- Android uses an adaptive icon with separate background, foreground, and monochrome resources. The notification small icon is a monochrome T.

The palette is ink `#101222`, violet `#BEADFF`, lime `#CAF59A`, and light `#F5F3FF`. Status must remain understandable through text and accessibility labels, not color alone. Incoming-call and incoming-file menu-bar symbols retain priority over the idle brand mark.

The canonical geometry lives in `scripts/generate-brand-assets.swift`. Regenerate from the repository root on macOS:

```sh
xcrun swift scripts/generate-brand-assets.swift .
python3 scripts/format-code.py
```

The production artwork is deterministic vector geometry with native-size PNG exports; it does not depend on an AI-generated presentation image or a downloaded font.

## Preserved identities

The product was previously called Androfest. User-facing branding, Swift projects/modules/source directories, app and helper executable names, Android application/theme class names, build outputs and current tooling use Twinvia. The shared Kotlin contract package is `dev.twinvia.protocol`. The Xcode project and scheme are `Twinvia`.

The following names remain deliberately compatible with installations made before the source rename:

| Retained name | Why it stays |
| --- | --- |
| `dev.androfest.android` application ID and Android component namespace | Preserve installed-app data, permissions, notification-listener identity, explicit component references and helper authorization. A product rebrand does not require changing this identity. |
| `dev.androfest.macos` and `dev.androfest.bluetooth` bundle IDs | Preserve application identity, preferences and permission association. |
| Keychain service names, Keystore aliases, caches and helper IPC paths | Keep saved device trust, TLS keys and existing helper activation usable; do not silently create new credentials. |
| Existing HMAC domains, wire/service identifiers and pairing QR scheme | Keep old and new peers interoperable without rescanning or inventing a protocol migration. |
| Notification identifiers | Allow existing delivered notifications to be updated/removed consistently. |
| Legacy signing-variable, isolated-test-property and helper-JAR aliases | Older local commands and the original 0.9.0 release kit remain usable; current examples use Twinvia names. |

Names inside fixed cryptographic test fixtures and historical 0.9.0 release binaries are not rewritten. The published release assets and checksums remain immutable; current source naming can differ from that earlier build.

Mac navigation accepts both `twinvia://` and the existing `androfest://` scheme. Navigation URLs never place a call without confirmation. Pairing wire values are unchanged. New received files use `Downloads/Twinvia`; previously received files in the legacy downloads folder are left intact. The optional shell clipboard helper should be reactivated after installing an update if its status is not ready.

The rebrand does not add capabilities or change the documented BLE/call-audio limitations. Repository visibility and source review are separate from any future public release or trademark registration.
