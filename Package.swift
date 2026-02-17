// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Replay",
    platforms: [
        .macOS(.v10_15),
        .macCatalyst(.v13),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6),
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
    traits: [
        .trait(name: "AsyncHTTPClient")
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.24.0"),
    ],
    targets: [
        .target(
            name: "Replay",
            dependencies: [
                .product(
                    name: "AsyncHTTPClient",
                    package: "async-http-client",
                    condition: .when(traits: ["AsyncHTTPClient"])
                )
            ]
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
