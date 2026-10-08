// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Quadrant",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Quadrant", targets: ["Quadrant"])
    ],
    targets: [
        .executableTarget(name: "Quadrant"),
        .testTarget(name: "QuadrantTests", dependencies: ["Quadrant"])
    ]
)
