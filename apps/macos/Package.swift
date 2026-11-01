// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Twinvia",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Twinvia", targets: ["Twinvia"])],
    dependencies: [
        .package(path: "../../shared/protocol/swift"),
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        .executableTarget(
            name: "Twinvia",
            dependencies: [
                .product(name: "TwinviaProtocol", package: "swift"), .product(name: "Sparkle", package: "Sparkle"),
            ],
            exclude: ["Assets.xcassets"]
        ),
        .testTarget(name: "TwinviaTests", dependencies: ["Twinvia"]),
    ]
)
