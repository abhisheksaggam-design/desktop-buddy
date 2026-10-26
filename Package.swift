// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DesktopBuddyV2",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DesktopBuddyV2",
            path: "Sources/DesktopBuddy"
        )
    ]
)
