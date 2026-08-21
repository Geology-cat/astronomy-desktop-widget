// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AstronomyDesktopWidget",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AstronomyCore", targets: ["AstronomyCore"]),
        .executable(name: "AstronomyWidget", targets: ["AstronomyWidget"])
    ],
    targets: [
        .target(name: "AstronomyCore"),
        .executableTarget(
            name: "AstronomyWidget",
            dependencies: ["AstronomyCore"]
        ),
        .testTarget(
            name: "AstronomyCoreTests",
            dependencies: ["AstronomyCore"]
        )
    ]
)
