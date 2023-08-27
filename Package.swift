// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "macHotkeys",
    dependencies: [
        .package(name: "Down", url: "https://github.com/johnxnguyen/Down.git", from: "0.9.0")
    ],
    targets: [
        .target(
            name: "macHotkeys",
            dependencies: [
                .product(name: "Down", package: "Down")
            ]),
        .testTarget(
            name: "mic",
            dependencies: ["macHotkeys"]),
    ]
)
