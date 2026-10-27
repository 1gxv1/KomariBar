// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KomariBar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "KomariBar", targets: ["KomariBar"]),
        .library(name: "KomariBarCore", targets: ["KomariBarCore"])
    ],
    targets: [
        .target(name: "KomariBarCore"),
        .executableTarget(name: "KomariBar", dependencies: ["KomariBarCore"]),
        .testTarget(name: "KomariBarCoreTests", dependencies: ["KomariBarCore"])
    ],
    swiftLanguageModes: [.v5]
)
