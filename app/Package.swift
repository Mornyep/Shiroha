// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VNLauncher", platforms: [.macOS(.v14)],
    products: [
        .executable(name: "VNLauncher", targets: ["VNLauncher"]),
        .executable(name: "VNInspect", targets: ["VNInspect"]),
    ],
    targets: [
        .target(name: "VNCore"), .executableTarget(name: "VNInspect", dependencies: ["VNCore"]),
        .executableTarget(name: "VNLauncher", dependencies: ["VNCore"]),
        .testTarget(name: "VNCoreTests", dependencies: ["VNCore"]),
    ], swiftLanguageModes: [.v6])
