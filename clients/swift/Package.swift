// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ZMRClient",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ZMRClient", targets: ["ZMRClient"]),
        .executable(name: "ZMRFakeSession", targets: ["ZMRFakeSession"])
    ],
    targets: [
        .target(name: "ZMRClient"),
        .executableTarget(name: "ZMRFakeSession", dependencies: ["ZMRClient"]),
        .testTarget(name: "ZMRClientTests", dependencies: ["ZMRClient"])
    ]
)
