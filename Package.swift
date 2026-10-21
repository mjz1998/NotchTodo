// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchTodo",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "NotchTodo", path: "Sources/NotchTodo")
    ]
)
