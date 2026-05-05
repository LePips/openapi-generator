// swift-tools-version:6.1

import PackageDescription

let package = Package(
    name: "GeneratedAPI",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "GeneratedAPI", targets: ["GeneratedAPI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/kean/Get", from: "2.1.0"),
        .package(url: "https://github.com/apple/swift-algorithms", from: "1.2.0")
    ],
    targets: [
        .target(name: "GeneratedAPI", dependencies: [
            .product(name: "Get", package: "Get"),
            .product(name: "Algorithms", package: "swift-algorithms")
        ], path: "Sources")
    ]
)
