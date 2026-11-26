// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WenBarCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "WenBarCore",
            targets: ["WenBarCore"]
        )
    ],
    targets: [
        .target(
            name: "WenBarCore"
        ),
        .testTarget(
            name: "WenBarCoreTests",
            dependencies: ["WenBarCore"]
        )
    ]
)
