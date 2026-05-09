// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ZMRClient",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ZMRClient", targets: ["ZMRClient"])
    ],
    targets: [
        .target(name: "ZMRClient")
    ]
)
