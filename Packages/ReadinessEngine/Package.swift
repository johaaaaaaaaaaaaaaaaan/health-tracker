// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReadinessEngine",
    platforms: [.iOS("26.0"), .macOS("14.0")],
    products: [
        .library(name: "ReadinessEngine", targets: ["ReadinessEngine"]),
    ],
    targets: [
        .target(name: "ReadinessEngine", path: "Sources/ReadinessEngine"),
        .testTarget(name: "ReadinessEngineTests", dependencies: ["ReadinessEngine"], path: "Tests/ReadinessEngineTests"),
    ]
)
