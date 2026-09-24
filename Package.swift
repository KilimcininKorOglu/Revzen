// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Revzen",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "RevzenCore"),
        .executableTarget(
            name: "Revzen",
            dependencies: ["RevzenCore"]
        ),
        .testTarget(
            name: "RevzenTests",
            dependencies: ["Revzen"]
        ),
        .testTarget(
            name: "RevzenCoreTests",
            dependencies: ["RevzenCore"]
        )
    ]
)
