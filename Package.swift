// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Aria",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Aria", targets: ["Aria"])
    ],
    targets: [
        .target(
            name: "CSpeexDSP",
            path: "Sources/CSpeexDSP",
            sources: ["src"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("src"),
                .headerSearchPath("include/speex"),
                .define("HAVE_CONFIG_H"),
                .unsafeFlags(["-include", "config.h", "-w"])
            ]
        ),
        .executableTarget(
            name: "Aria",
            dependencies: ["CSpeexDSP"],
            path: "Sources/Aria"
        ),
        .testTarget(
            name: "AriaTests",
            dependencies: ["Aria"],
            path: "Tests/AriaTests"
        )
    ]
)
