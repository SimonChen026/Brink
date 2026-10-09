// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "BrinkCore",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BrinkCore", targets: ["BrinkCore"]),
        .executable(name: "brink-cli", targets: ["brink-cli"])
    ],
    targets: [
        .target(
            name: "BrinkCore",
            resources: [.copy("Resources/Scenarios"), .copy("Resources/Exams")]
        ),
        .executableTarget(
            name: "brink-cli",
            dependencies: ["BrinkCore"]
        ),
        .testTarget(
            name: "BrinkCoreTests",
            dependencies: ["BrinkCore"]
        )
    ]
)
