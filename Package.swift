// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SessionHub",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "SessionHub",
            path: "Sources"
        )
    ]
)
