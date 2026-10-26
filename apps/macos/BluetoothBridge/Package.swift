// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AndrofestBluetoothBridge",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../../.tooling/google-nearby"),
        .package(path: "../../../shared/protocol/swift"),
    ],
    targets: [
        .executableTarget(
            name: "AndrofestBleBridge",
            dependencies: [
                .product(name: "NearbyConnections", package: "google-nearby"),
                .product(name: "AndrofestProtocol", package: "swift"),
            ])
    ]
)
