// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Keypress",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.0"),
    ],
    targets: [
        .target(
            name: "KeypressCore",
            dependencies: [],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .executableTarget(
            name: "Keypress",
            dependencies: [
                "KeypressCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Keypress",
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "KeypressTests",
            dependencies: ["Keypress", "KeypressCore"],
            path: "Tests",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]
        ),
    ]
)
