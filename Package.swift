// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AmoreKit",
    platforms: [.macOS(.v14)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "AmoreLicensing",
            targets: ["AmoreLicensing"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/jwt-kit.git", from: "5.0.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.1.0"),
    ],
    targets: [
        .target(
            name: "AmoreLicensing",
            dependencies: [
                .product(name: "JWTKit", package: "jwt-kit"),
            ],
        ),
        .testTarget(
            name: "AmoreLicensingTests",
            dependencies: [
                "AmoreLicensing",
                .product(name: "JWTKit", package: "jwt-kit"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
