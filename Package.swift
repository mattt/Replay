// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Replay",
    platforms: [
        .macOS(.v14),
        .macCatalyst(.v17),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "Replay",
            targets: ["Replay"]
        ),
        .plugin(
            name: "ReplayPlugin",
            targets: ["ReplayPlugin"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "Replay"
        ),
        .executableTarget(
            name: "ReplayCLI",
            dependencies: [
                "Replay",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .plugin(
            name: "ReplayPlugin",
            capability: .command(
                intent: .custom(
                    verb: "replay",
                    description: "HTTP recording and playback utilities"
                ),
                permissions: [
                    .writeToPackageDirectory(reason: "Manage HAR replay archives")
                ]
            ),
            dependencies: ["ReplayCLI"]
        ),
        .testTarget(
            name: "ReplayTests",
            dependencies: ["Replay"]
        ),
        .testTarget(
            name: "IntegrationTests",
            dependencies: ["Replay"],
            resources: [
                .copy("Replays")
            ]
        ),
    ]
)
