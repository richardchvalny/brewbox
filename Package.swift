// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Brewbox",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Brewbox",
            path: "Sources/Brewbox"
        )
    ]
)
