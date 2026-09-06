// swift-tools-version: 6.3

import PackageDescription

/// Shared language checks keep maintenance modules consistent on macOS and Linux.
let strictSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .treatAllWarnings(as: .error),
]

/// Maintenance tools build independently of compiler sources and binary artifacts.
let package = Package(
    name: "SwiftToolchainIOS",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "toolchain", targets: ["ToolchainCLI"])],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.8.2"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin.git", exact: "1.4.0"),
    ],
    targets: [
        .target(name: "ToolchainSupport", swiftSettings: strictSettings),
        .executableTarget(
            name: "ToolchainCLI",
            dependencies: [
                "ToolchainSupport",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Tools/ToolchainCLI",
            swiftSettings: strictSettings,
        ),
        .testTarget(
            name: "ToolchainSupportTests",
            dependencies: ["ToolchainSupport"],
            swiftSettings: strictSettings,
        ),
    ],
    swiftLanguageModes: [.v6],
)
