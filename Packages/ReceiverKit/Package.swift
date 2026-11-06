// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ReceiverKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ReceiverKit", targets: ["ReceiverKit"]),
    ],
    targets: [
        // Real-time safe pieces (ring buffer + render callback) live in C so the
        // audio thread never touches Swift runtime, locks or allocation.
        .target(name: "CAudioCore"),
        .target(name: "ReceiverKit", dependencies: ["CAudioCore"]),
        .testTarget(
            name: "ReceiverKitTests",
            dependencies: ["ReceiverKit", "CAudioCore"]
        ),
    ]
)
