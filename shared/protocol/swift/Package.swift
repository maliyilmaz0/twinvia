// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AndrofestProtocol",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AndrofestProtocol", targets: ["AndrofestProtocol"])],
    targets: [
        .target(name: "AndrofestProtocol"),
        .testTarget(name: "AndrofestProtocolTests", dependencies: ["AndrofestProtocol"]),
    ]
)
