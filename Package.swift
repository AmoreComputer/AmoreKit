// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// AmoreStore depends on Foundation currency metadata (NumberFormatter) that is
// only reliable on Apple platforms, so it is built only there.
var products: [Product] = [
    .library(
        name: "AmoreLicensing",
        targets: ["AmoreLicensing"]
    ),
]

var targets: [Target] = [
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
        ]
    ),
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
]

#if canImport(Darwin)
products.append(
    .library(
        name: "AmoreStore",
        targets: ["AmoreStore"]
    )
)
targets.append(.target(name: "AmoreStore"))
targets.append(
    .testTarget(
        name: "AmoreStoreTests",
        dependencies: ["AmoreStore"]
    )
)
#endif

let package = Package(
    name: "AmoreKit",
    platforms: [
        .macOS(.v14),
    ],
    products: products,
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", "3.8.0"..<"5.0.0"),
        .package(url: "https://github.com/vapor/jwt-kit.git", from: "5.0.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.1.0"),
    ],
    targets: targets,
    swiftLanguageModes: [.v6]
)
