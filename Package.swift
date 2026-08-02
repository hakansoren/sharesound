// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShareSound",
    // Liquid Glass (glassEffect, GlassEffectContainer, .glassProminent buttons)
    // arrived in macOS 26; the interface is built on that visual language.
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "ShareSound", targets: ["ShareSound"]),
        .library(name: "ShareSoundKit", targets: ["ShareSoundKit"]),
    ],
    targets: [
        .target(
            name: "ShareSoundKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "ShareSound",
            dependencies: ["ShareSoundKit"],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ShareSoundKitTests",
            dependencies: ["ShareSoundKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
