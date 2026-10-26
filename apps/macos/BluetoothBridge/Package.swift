// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TwinviaBluetoothBridge",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../../.tooling/google-nearby"),
        .package(path: "../../../shared/protocol/swift"),
    ],
    targets: [
        .executableTarget(
            name: "TwinviaBleBridge",
            dependencies: [
                .product(name: "NearbyConnections", package: "google-nearby"),
                .product(name: "TwinviaProtocol", package: "swift"),
            ])
    ]
)
