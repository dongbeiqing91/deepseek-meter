// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DeepSeekMeter",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DeepSeekMeter",
            path: "Sources/DeepSeekMeter",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
