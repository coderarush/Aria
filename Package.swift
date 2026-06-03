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
        .executableTarget(
            name: "Aria",
            path: "Sources/Aria"
        ),
        .testTarget(
            name: "AriaTests",
            dependencies: ["Aria"],
            path: "Tests/AriaTests"
        )
    ]
)
