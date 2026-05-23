// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "simtouch",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "simtouch", targets: ["simtouch"]),
    ],
    targets: [
        .target(
            name: "CSimTouchShim",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "simtouch",
            dependencies: ["CSimTouchShim"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Foundation"),
            ]
        ),
    ]
)
