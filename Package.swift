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
                // The Swift optimizer miscompiles SwiftUI actor-isolation in this
                // toolchain. History: on macOS 26.3 / Swift 6.3, whole-module
                // optimization made release builds crash on the first SwiftUI control
                // tap (swift_task_isCurrentExecutorWithFlags, EXC_BAD_ACCESS), fixed
                // by -no-whole-module-optimization. On macOS 26.3.1 the same family
                // returned EVEN WITHOUT WMO (EXC_BREAKPOINT in
                // MainActor.assumeIsolated under _ButtonGesture). Debug-level codegen
                // has never crashed across all three recurrences, so release for the
                // Aria target is pinned to -Onone until the optimizer bug is bisected.
                // Perf impact is negligible: the hot real-time path (Speex AEC) is C,
                // and everything else waits on network/disk. No-op in debug.
                .unsafeFlags(["-Onone", "-no-whole-module-optimization"], .when(configuration: .release))
            ]
        ),
        .testTarget(
            name: "AriaTests",
            dependencies: ["Aria"],
            path: "Tests/AriaTests"
        )
    ]
)
