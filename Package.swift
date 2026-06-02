// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Friday",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Friday", targets: ["Friday"])
    ],
    targets: [
        .executableTarget(
            name: "Friday",
            path: "Sources/Friday"
        ),
        .testTarget(
            name: "FridayTests",
            dependencies: ["Friday"],
            path: "Tests/FridayTests"
        )
    ]
)
