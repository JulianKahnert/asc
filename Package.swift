// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ASC",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "asc", targets: ["ASCExecutable"])
    ],
    dependencies: [
        .package(url: "https://github.com/AvdLee/appstoreconnect-swift-sdk.git", branch: "master"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.1"),
    ],
    targets: [
        // Library target – importable by both the executable wrapper and tests.
        .target(
            name: "ASC",
            dependencies: [
                .product(name: "AppStoreConnect-Swift-SDK", package: "appstoreconnect-swift-sdk"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        // Thin executable wrapper that just calls ASCMain.main().
        .executableTarget(
            name: "ASCExecutable",
            dependencies: [
                .target(name: "ASC")
            ]
        ),
        // Test target using Swift Testing.
        .testTarget(
            name: "ASCTests",
            dependencies: [
                .target(name: "ASC"),
                .product(name: "AppStoreConnect-Swift-SDK", package: "appstoreconnect-swift-sdk")
            ]
        )
    ]
)
