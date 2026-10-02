// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LocalTime",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LocalTime", targets: ["LocalTime"])
    ],
    targets: [
        .executableTarget(
            name: "LocalTime",
            path: "Sources/LocalTime",
            exclude: ["Assets.xcassets"]
        ),
        .testTarget(
            name: "LocalTimeTests",
            dependencies: ["LocalTime"],
            path: "Tests/LocalTimeTests"
        )
    ]
)
