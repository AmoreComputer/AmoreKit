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
        .library(
            name: "AmoreStore",
            targets: ["AmoreStore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", "3.8.0"..<"5.0.0"),
        .package(url: "https://github.com/vapor/jwt-kit.git", from: "5.0.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.1.0"),
    ],
    targets: [
        .target(
            name: "AmoreJWT",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
            ]
        ),
        .target(
            name: "AmoreLicensing",
            dependencies: [
                "AmoreJWT",
                .product(name: "Crypto", package: "swift-crypto"),
            ],
        ),
        .target(name: "AmoreStore"),
        .testTarget(
            name: "AmoreJWTTests",
            dependencies: [
                "AmoreJWT",
                .product(name: "JWTKit", package: "jwt-kit"),
            ]
        ),
        .testTarget(
            name: "AmoreLicensingTests",
            dependencies: [
                "AmoreLicensing",
                "AmoreJWT",
                .product(name: "JWTKit", package: "jwt-kit"),
            ]
        ),
        .testTarget(
            name: "AmoreStoreTests",
            dependencies: ["AmoreStore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
