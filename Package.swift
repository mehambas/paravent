// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Paravent",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "Paravent", targets: ["Paravent"])],
    targets: [
        .target(name: "ParaventCore"),
        .executableTarget(name: "Paravent", dependencies: ["ParaventCore"]),
        .testTarget(name: "ParaventCoreTests", dependencies: ["ParaventCore"])
    ],
    swiftLanguageModes: [.v5]
)
