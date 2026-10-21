// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CompClean",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "CompClean", targets: ["CompClean"]),
        // Its own product gives Xcode a "CompCleanUI" scheme to render previews with.
        .library(name: "CompCleanUI", targets: ["CompCleanUI"]),
    ],
    targets: [
        .target(name: "CleanerCore"),
        // All screens live in a library so Xcode can render their previews.
        .target(name: "CompCleanUI", dependencies: ["CleanerCore"]),
        .executableTarget(name: "CompClean", dependencies: ["CompCleanUI"]),
        .executableTarget(name: "compclean-preview", dependencies: ["CleanerCore"]),
        .testTarget(name: "CleanerCoreTests", dependencies: ["CleanerCore"]),
    ]
)
