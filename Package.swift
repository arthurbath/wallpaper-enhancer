// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WallpaperEnhancer",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "WallpaperEnhancer", targets: ["WallpaperEnhancer"])],
    targets: [
        .target(name: "EnhancerCore"),
        .executableTarget(name: "WallpaperEnhancer", dependencies: ["EnhancerCore"]),
        .testTarget(name: "EnhancerCoreTests", dependencies: ["EnhancerCore"])
    ]
)
