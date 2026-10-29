# Signed in-app updates

Twinvia downloads published binaries from GitHub Releases. It does not clone the repository, execute source from a branch, or replace an app with an unverified download. Update checks require internet independently of the offline phone bridge.

## macOS

The app embeds Sparkle **2.10.1**, pinned by exact version and package checksum. **General → Software updates → Check for updates** opens Sparkle's standard update UI. Sparkle owns download, signature validation, installation, rollback handling and relaunch. Archive verification is required before extraction. The public Ed25519 key is in `Info.plist`; the private seed is excluded from source control.

The feed is `https://github.com/maliyilmaz0/twinvia/releases/latest/download/appcast.xml`. Only a manually published stable release appears on this channel. Background checks are opt-in through the Mac update card; automatic installation is off by default. Existing developer previews without this updater need one trusted installation of a build containing it first. The updater does not turn an ad-hoc build into a notarized distribution; Developer ID and notarization remain separate release requirements.

## Android

**Settings → Updates** checks the same stable channel. The app verifies a detached Ed25519 signature over `Twinvia Android Update v1\0` plus the exact manifest bytes. It validates the GitHub repository/asset URL, signed byte count, SHA-256, package name, higher version code and the installed signing certificate before opening Android's installer. Downloads use app-private cache storage and a narrowly scoped FileProvider grant. Android may first ask the user to allow installations from Twinvia. Installation always goes through the system confirmation UI.

Checks on app launch are opt-in. No phone connection or ADB is needed. Failures leave the installed app and pairing data intact.

### Older APK signing identities

Earlier preview CI jobs generated temporary debug keys. A new APK cannot update those installations using an unrelated signing identity. Twinvia reports that mismatch and does not uninstall, erase data or bypass Android checks. A migration must be planned after checking the actual installed certificate and available old key; data-preserving replacement cannot be promised if that key is unavailable.

Trusted `main` push builds now use a persistent Android distribution signing key from GitHub Actions secrets. Pull requests/forks use ordinary disposable debug signing, never the distribution key. The source variant is still a developer/debug build; persistent signing alone does not claim release hardening or Google Play compliance.

## Publication

1. Increment both Android `versionCode` and Mac `CFBundleVersion`, and keep the marketing versions aligned. Never reuse a published version/tag.
2. Merge through all required checks and wait for a successful trusted **Build and test** push run on `main`.
3. Run **Publish developer preview** with that run ID. Select `stable=true` only when the signed in-app channel should offer the build; the default remains an explicit prerelease.
4. The workflow packages the tested binaries, signs `update-manifest.json`/`update-manifest.sig`, and produces a Sparkle `appcast.xml` containing an Ed25519 signature of the Mac archive. It validates the signing key against the embedded public key and refreshes SHA256SUMS before uploading.
5. Verify a real upgrade on both platforms before describing installation/relaunch as device-tested. An immutable release or passing compilation is not that evidence.

The repository secrets are `TWINVIA_UPDATE_PRIVATE_KEY`, `TWINVIA_ANDROID_KEYSTORE`, and `TWINVIA_ANDROID_KEYSTORE_PASSWORD`. They are exposed only to trusted publication/main-build steps. Initial local backups live outside the checkout under `~/.config/twinvia-signing/`, with private directory/file permissions. Back these up securely. Do not paste them into logs, issues, documentation, or source control. Key rotation requires an explicit compatibility/migration plan, never silently regenerating keys.

The current released 0.9.0 preview has not been overwritten. Until a new signed stable release is published, update checks may report that no signed stable update exists.

References: [Sparkle setup and signatures](https://sparkle-project.org/documentation/), [Android install-source approval](https://developer.android.com/reference/android/content/pm/PackageManager#canRequestPackageInstalls()), [PackageInstaller](https://developer.android.com/reference/android/content/pm/PackageInstaller).
