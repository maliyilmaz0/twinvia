// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Twinvia",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Twinvia", targets: ["Twinvia"])],
    dependencies: [.package(path: "../../shared/protocol/swift")],
    targets: [
        .executableTarget(
            name: "Twinvia",
            dependencies: [.product(name: "TwinviaProtocol", package: "swift")],
            exclude: ["Assets.xcassets"]
        ),
        .testTarget(name: "TwinviaTests", dependencies: ["Twinvia"]),
    ]
)
