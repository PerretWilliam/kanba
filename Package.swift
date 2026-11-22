// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Kanban",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(name: "Kanban", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "KanbanTests", dependencies: ["Kanban"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
