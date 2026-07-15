// swift-tools-version:6.1

import PackageDescription

let package = Package(
    name: "SpritePencilKit",
    platforms: [
        // No native macOS: several sources import UIKit unguarded.
        // (Mac Catalyst builds from the iOS platform and is unaffected.)
        .iOS(.v17), .visionOS(.v1)
    ],
    products: [
        .library(
            name: "SpritePencilKit",
            targets: ["SpritePencilKit"]),
    ],
    targets: [
        .target(
            name: "SpritePencilKit"),
        .testTarget(
            name: "SpritePencilKitTests",
            dependencies: ["SpritePencilKit"])
    ]
)
