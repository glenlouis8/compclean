// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Suds",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Suds", targets: ["Suds"]),
        // Its own product gives Xcode a "SudsUI" scheme to render previews with.
        .library(name: "SudsUI", targets: ["SudsUI"]),
    ],
    targets: [
        .target(name: "CleanerCore"),
        // All screens live in a library so Xcode can render their previews.
        .target(name: "SudsUI", dependencies: ["CleanerCore"]),
        .executableTarget(name: "Suds", dependencies: ["SudsUI", "CleanerCore"]),
        .executableTarget(name: "suds-preview", dependencies: ["CleanerCore"]),
        .testTarget(name: "CleanerCoreTests", dependencies: ["CleanerCore"]),
    ]
)
