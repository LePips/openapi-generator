// swift-tools-version:6.1

import PackageDescription

let package = Package(
    name: "MyOpenAPISDK",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "MyOpenAPISDK", targets: ["MyOpenAPISDK"]),
    ],
    dependencies: [
        .package(url: "https://github.com/kean/Get", from: "2.1.0"),
    ],
    targets: [
        .target(
            name: "MyOpenAPISDK",
            dependencies: [
                .product(name: "Get", package: "Get"),
            ],
            path: "Sources"
        )
    ]
)
