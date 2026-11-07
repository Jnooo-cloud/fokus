// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Fokus",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ZoneCore", targets: ["ZoneCore"]),
        .executable(name: "Fokus", targets: ["Fokus"]),
        .executable(name: "fokus-mcp", targets: ["FokusMCP"])
    ],
    targets: [
        .target(name: "ZoneCore"),
        // Built with the Command Line Tools alone, so no Xcode is needed for the local app.
        .executableTarget(name: "Fokus", dependencies: ["ZoneCore"], path: ".",
                          exclude: ["Sources/Zone/FilterController.swift"], sources: ["Sources/Zone", "Shared"]),
        // Read-only MCP server so Claude can look at the same data the app shows.
        .executableTarget(name: "FokusMCP", dependencies: ["ZoneCore"],
                          // A single-threaded stdio loop; strict actor checks add nothing here.
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "ZoneCoreTests", dependencies: ["ZoneCore"])
    ]
)
