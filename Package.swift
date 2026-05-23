// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SimTouch",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "SimTouchCore", targets: ["SimTouchCore"]),
        .executable(name: "simtouch", targets: ["simtouch"]),
        .executable(name: "simtouch-capture", targets: ["SimTouchCapture"]),
    ],
    targets: [
        .target(
            name: "CSimTouchShim",
            publicHeadersPath: "include"
        ),
        .target(
            name: "SimTouchCore",
            dependencies: ["CSimTouchShim"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Foundation"),
            ]
        ),
        .executableTarget(
            name: "simtouch",
            dependencies: ["SimTouchCore"],
            path: "Sources/simtouchCLI"
        ),
        .executableTarget(
            name: "SimTouchCapture",
            dependencies: ["SimTouchCore"],
            path: "Sources/SimTouchCapture",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Foundation"),
            ]
        ),
    ]
)
