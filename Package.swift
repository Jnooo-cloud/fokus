// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Fokus",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ZoneCore", targets: ["ZoneCore"]),
        .executable(name: "Fokus", targets: ["Fokus"])
    ],
    targets: [
        .target(name: "ZoneCore"),
        // Built with the Command Line Tools alone, so no Xcode is needed for the local app.
        .executableTarget(name: "Fokus", dependencies: ["ZoneCore"], path: ".",
                          exclude: ["Sources/Zone/FilterController.swift"], sources: ["Sources/Zone", "Shared"]),
        .testTarget(name: "ZoneCoreTests", dependencies: ["ZoneCore"])
    ]
)
