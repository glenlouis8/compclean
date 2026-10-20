// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CompClean",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "CleanerCore"),
        .executableTarget(name: "CompClean", dependencies: ["CleanerCore"]),
        .executableTarget(name: "compclean-preview", dependencies: ["CleanerCore"]),
        .testTarget(name: "CleanerCoreTests", dependencies: ["CleanerCore"]),
    ]
)
