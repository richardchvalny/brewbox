// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HomebrewToolbox",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "HomebrewToolbox",
            path: "Sources/HomebrewToolbox"
        )
    ]
)
