// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TwinviaProtocol",
    platforms: [.macOS(.v14)],
    products: [.library(name: "TwinviaProtocol", targets: ["TwinviaProtocol"])],
    targets: [
        .target(name: "TwinviaProtocol"),
        .testTarget(name: "TwinviaProtocolTests", dependencies: ["TwinviaProtocol"]),
    ]
)
