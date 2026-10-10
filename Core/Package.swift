// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "StampCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "StampCore", targets: ["StampCore"]),
        .executable(name: "stampcli", targets: ["stampcli"]),
    ],
    targets: [
        .target(name: "StampCore"),
        .executableTarget(name: "stampcli", dependencies: ["StampCore"]),
        .testTarget(name: "StampCoreTests", dependencies: ["StampCore"]),
    ]
)
