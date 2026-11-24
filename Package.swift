// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ShotNamer",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ShotNamerCore"),
        .executableTarget(name: "ShotNamer", dependencies: ["ShotNamerCore"]),
        .testTarget(name: "ShotNamerCoreTests", dependencies: ["ShotNamerCore"]),
    ],
    swiftLanguageModes: [.v5]
)
