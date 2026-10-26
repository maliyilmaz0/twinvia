# Google Nearby product patch

Upstream: https://github.com/google/nearby

Pinned revision: `f3e0f907adef395fd20fd8554e103bcc7d1b8fd7`

License: Apache-2.0. The build fetches the upstream source into the ignored `.tooling/google-nearby` directory and retains upstream license notices. This directory contains a small product integration patch, not a vendored SDK or OS binary.

`ble-transport.patch` exposes SDK flag setters used to disable transport upgrades and defers BLE service registration until CoreBluetooth has a usable state. Some setter names retain upstream integration terminology; the production helper explicitly disables Apple peer-to-peer Wi-Fi and all non-BLE upgrades. The patch does not change macOS or Android security policy.

`scripts/prepare-nearby-sdk.py` verifies the revision, initializes submodules, and checks whether the patch is unapplied or already applied. It refuses a different checkout rather than discarding local changes. Review the patch and run build/device tests before updating the revision.
