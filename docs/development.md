# Development guide

## Toolchain

Use full Xcode with Swift 6 and command-line tools selected, JDK 21, Python 3.10+, Git, and Android SDK 37.0 / build tools 36.0.0 / platform tools. Set `JAVA_HOME` and `ANDROID_HOME` explicitly when your environment differs. Android Studio's **Gradle JVM must be JDK 21**; do not let its bundled newer JVM override the project's Gradle runtime.

`./scripts/doctor.sh` checks the local toolchain. `scripts/common.sh` discovers the standard macOS SDK locations. Build scripts operate relative to the repository root and do not require personal absolute paths or signing credentials in source.

## Entry points

| Command | Purpose |
| --- | --- |
| `python3 scripts/format-code.py` | Format admitted Swift/Kotlin source using swift-format and checksum-pinned ktfmt 0.63. |
| `./scripts/check.sh` | Publication policy, tooling unit tests, and formatting checks. |
| `./scripts/test.sh --console=plain` | Shared Swift, macOS, Kotlin protocol, and Android application unit tests. |
| `./scripts/build-android.sh` | Clipboard helper, Android tests, lint, and debug APK. |
| `./scripts/build-macos.sh` | Pinned Nearby source, BLE helper, Xcode app, nested signing, and packaged development app. |
| `python3 scripts/check-publication.py` | Check tracked and prospective source paths; also catch force-added ignored files. |

`format-code.py --check --language kotlin` runs on Linux. Swift formatting requires Xcode's swift-format. Do not format generated files or downloaded dependencies.

## IDEs and dependencies

Open `apps/android` in Android Studio. Open `apps/macos/Twinvia.xcodeproj` in Xcode. The Swift package in `apps/macos` supports unit tests independently of app packaging. `apps/macos/BluetoothBridge` is a separate Swift 5.9 package because the upstream Google SDK is isolated from the Swift 6 UI/session target.

The Google Nearby source revision is pinned in `prepare-nearby-sdk.py`; changing it requires reviewing the product patch and running helper/device tests. A mismatched local checkout is rejected instead of reset. The patch and provenance live in `vendor/nearby/`. Do not copy the downloaded SDK into source control.

Shared contract changes require Kotlin and Swift tests plus shared fixtures/schema updates. Keep wire values compatible unless a protocol-version migration is explicitly designed. Renaming source folders must not change persisted Keychain/Keystore identifiers or pairing identities.

## Signing and packaging

Mac builds prefer the configured `TWINVIA_SIGNING_IDENTITY` or an installed Developer ID Application identity. Set it to `-` for ad-hoc CI builds. The helper is signed before the enclosing app. Build CI does not import certificates, prompt for Keychain access, notarize, deploy, or publish a release. The separate manual [preview release workflow](releasing.md) packages already-tested CI artifacts with narrowly scoped publication permission.

Android debug signing uses the developer/runner's debug keystore. Do not replace an installed APK using a differently signed artifact without a deliberate migration; this can require uninstalling and losing app state. Release signing credentials never belong in the repository.

## Continuous integration

Both `.github/workflows/ci.yml` and `.gitlab-ci.yml` are provided. They validate publication scope, run formatting/tooling checks, execute unit tests and Android lint, and build development artifacts. Reports and artifacts have explicit paths and expiry; local caches, captures, private app state, and broad `.artifacts/` archives are never uploaded.

GitHub uses hosted Ubuntu and macOS runners. GitLab's Android job uses a Linux Docker runner with JDK 21 and bootstraps checksum-pinned official Android command-line tools. Its macOS job needs a **shell runner tagged `macos`** with Xcode, Python, Git, and the required command-line tools installed. Untrusted merge requests must use disposable runners without production credentials or personal devices. The pipeline does not run real Bluetooth integration tests automatically.

GitHub also runs redacted full-history secret scanning, workflow linting and Python correctness checks, exports Swift coverage, and submits resolved Android dependencies from a separate trusted main-branch workflow. CodeQL and dependency-review configurations are eligibility-gated; a skipped native scanner is not a successful vulnerability scan. See [GitHub security controls](github-security.md) for active settings, pinned tools, plan limitations and release requirements.

CI configuration can be checked locally, but server scheduling, runner tags, artifact permissions, and merge-request status require validation after the remote repository is supplied. Included configuration is not evidence that a remote pipeline has run.

## Publication hygiene

Run the publication guard before staging and again after staging. Review `git diff --cached --stat` and `git diff --cached` before a push. `.gitignore` does not untrack files that were committed previously: remove such files from the index deliberately without deleting local copies, then rerun the guard. Do not force-add private investigations, credentials, captures, generated binaries, or device reports.

The guard checks an explicit product path allowlist, generated/credential extensions, file sizes, symlinks, and common credential signatures. It reports paths without printing suspected secret content. It is a useful gate, not a complete secret scanner or a substitute for review.

The Android build uses Gradle **9.8.2**, AGP **9.4.1**, and built-in Android Kotlin support. The Kotlin compiler/plugins remain pinned to **2.4.21**. Compile SDK is **37**; target SDK remains **36**. Both the app and standalone clipboard probe apply the reviewed dependency patch policy in `apps/android/gradle/dependency-security.settings.gradle.kts`. Run `python3 scripts/test-dependency-policy.py` to verify real dependency resolution, version alignment, and preservation of newer versions.
