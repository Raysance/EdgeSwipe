// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EdgeSwipe",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "EdgeSwipe", targets: ["EdgeSwipe"]),
        .executable(name: "EdgeSwipeCheck", targets: ["EdgeSwipeCheck"]),
        .library(name: "EdgeSwipeCore", targets: ["EdgeSwipeCore"])
    ],
    targets: [
        .target(name: "EdgeSwipeCore"),
        .executableTarget(
            name: "EdgeSwipe",
            dependencies: ["EdgeSwipeCore"]
        ),
        .executableTarget(
            name: "EdgeSwipeCheck",
            dependencies: ["EdgeSwipeCore"]
        )
    ]
)
