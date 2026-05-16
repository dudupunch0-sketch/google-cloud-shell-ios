// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MobileCloudShellTerminal",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "MobileCloudShellCore",
            targets: ["MobileCloudShellCore"]
        )
    ],
    targets: [
        .target(name: "MobileCloudShellCore"),
        .testTarget(
            name: "MobileCloudShellCoreTests",
            dependencies: ["MobileCloudShellCore"]
        )
    ]
)
