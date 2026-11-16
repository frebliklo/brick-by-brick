// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BrickCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "BrickCore", targets: ["BrickCore"])],
    targets: [
        .target(name: "BrickCore", path: "BrickByBrick/Core"),
        .testTarget(name: "BrickCoreTests", dependencies: ["BrickCore"], path: "Tests/BrickCoreTests")
    ]
)
