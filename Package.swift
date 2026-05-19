// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SushiSpeak",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SushiSpeak",
            path: "Sources/SushiSpeak"
        )
    ]
)
