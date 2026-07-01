// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NeuroMetaSDKBinary",
    platforms: [
        .iOS(.v13),
        .macOS(.v12),
    ],
    products: [
        .library(
            name: "NeuroMetaSDK",
            targets: ["NeuroMetaSDK"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "NeuroMetaSDK",
            path: "NeuroMetaSDK.xcframework"
        ),
    ]
)
