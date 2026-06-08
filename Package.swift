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
            path: "Sources/Aria",
            swiftSettings: [
                // Whole-module optimization miscompiles SwiftUI actor-isolation in this
                // toolchain (Swift 6.3 / macOS 26.3): a release build crashes on the first
                // SwiftUI Button tap, inside swift_task_isCurrentExecutorWithFlags
                // (EXC_BAD_ACCESS, null executor identity). Per-file -O is fine — only the
                // cross-module pass breaks it. `make release` passes the same flag; this
                // keeps a bare `swift build -c release` safe too. No-op in debug.
                .unsafeFlags(["-no-whole-module-optimization"], .when(configuration: .release))
            ]
        ),
        .testTarget(
            name: "AriaTests",
            dependencies: ["Aria"],
            path: "Tests/AriaTests"
        )
    ]
)
