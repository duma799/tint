// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "tint",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "tint", targets: ["tint"]),
        .executable(name: "TintApp", targets: ["TintApp"]),
        .library(name: "TintCore", targets: ["TintCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        // Everything that isn't UI: colour maths, schemes, output, reloads,
        // wallpaper watching, the login service. Builds (and is tested) on
        // Linux too; the macOS-only parts are behind #if os(macOS).
        .target(name: "TintCore"),
        // The `tint` command.
        .executableTarget(
            name: "tint",
            dependencies: ["TintCore", .product(name: "ArgumentParser", package: "swift-argument-parser")]
        ),
        // The SwiftUI app (macOS only).
        .executableTarget(name: "TintApp", dependencies: ["TintCore"]),
        .testTarget(name: "TintCoreTests", dependencies: ["TintCore"]),
    ]
)
