// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FinderCut",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "FinderCut",
            path: "Sources/FinderCut"
        )
    ]
)
