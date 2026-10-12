// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MDPreview",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MDPreview",
            path: "Sources/MDPreview"
        )
    ]
)
