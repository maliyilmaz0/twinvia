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

The product was previously called Androfest. Existing package and bundle IDs, Swift modules, Keychain service names, Keystore aliases, protocol domains, pairing QR scheme, and helper executable names remain stable to preserve saved trust and platform permissions. `dev.androfest.android` and `dev.androfest.macos` are intentional compatibility identifiers, not stale display labels. The Xcode project/scheme and source/module paths also retain their original names.

Mac navigation accepts both `twinvia://` and the existing `androfest://` scheme. Navigation URLs never place a call without confirmation. Pairing wire values are unchanged. New received files use `Downloads/Twinvia`; previously received files in `Downloads/Androfest` are left intact. The optional shell clipboard helper should be reactivated after installing an update if its status is not ready.

The rebrand does not add capabilities or change the documented BLE/call-audio limitations. Repository visibility and source review are separate from any future public release or trademark registration.
