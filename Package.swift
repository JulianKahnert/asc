// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ASC",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "asc", targets: ["ASC"])
    ],
    dependencies: [
        .package(url: "https://github.com/AvdLee/appstoreconnect-swift-sdk.git", branch: "master"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.2"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "ASC",
            dependencies: [
                .product(name: "AppStoreConnect-Swift-SDK", package: "appstoreconnect-swift-sdk"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
        ),
    ]
)
