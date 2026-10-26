// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Androfest",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Androfest", targets: ["Androfest"])],
    dependencies: [.package(path: "../../shared/protocol/swift")],
    targets: [
        .executableTarget(
            name: "Androfest",
            dependencies: [.product(name: "AndrofestProtocol", package: "swift")],
            exclude: ["Assets.xcassets"]
        ),
        .testTarget(name: "AndrofestTests", dependencies: ["Androfest"]),
    ]
)
