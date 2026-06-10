// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Glidex",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "GlidexCore", targets: ["GlidexCore"]),
        .executable(name: "glidex", targets: ["glidex"]),
        .executable(name: "glidex-capture", targets: ["GlidexCapture"]),
    ],
    targets: [
        .target(
            name: "CGlidexShim",
            publicHeadersPath: "include"
        ),
        .target(
            name: "GlidexCore",
            dependencies: ["CGlidexShim"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Foundation"),
            ]
        ),
        .executableTarget(
            name: "glidex",
            dependencies: ["GlidexCore"],
            path: "Sources/glidexCLI"
        ),
        .executableTarget(
            name: "GlidexCapture",
            dependencies: ["GlidexCore"],
            path: "Sources/GlidexCapture",
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Foundation"),
            ]
        ),
        .testTarget(
            name: "GlidexCoreTests",
            dependencies: ["GlidexCore"],
            resources: [.process("Fixtures")]
        ),
    ]
)
