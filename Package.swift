// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pennyworth",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Pennyworth", targets: ["Pennyworth"]),
        .library(name: "PennyworthCore", targets: ["PennyworthCore"]),
    ],
    targets: [
        // UI-free engine: matching, providers, themes, config. Unit tested.
        .target(name: "PennyworthCore"),
        // The AppKit/SwiftUI launcher app.
        .executableTarget(name: "Pennyworth", dependencies: ["PennyworthCore"]),
        .testTarget(name: "PennyworthCoreTests", dependencies: ["PennyworthCore"]),
    ]
)
