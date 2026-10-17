// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CallQuits",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CallQuitsCore", targets: ["CallQuitsCore"]),
        .executable(name: "CallQuits", targets: ["CallQuits"])
    ],
    targets: [
        .target(name: "CallQuitsCore"),
        .executableTarget(name: "CallQuits", dependencies: ["CallQuitsCore"]),
        .testTarget(name: "CallQuitsCoreTests", dependencies: ["CallQuitsCore"]),
        .testTarget(name: "CallQuitsTests", dependencies: ["CallQuits"])
    ]
)
