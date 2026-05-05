// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "openapi-generator",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "openapi-generator", targets: ["GeneratorExecutable"]),
        .executable(name: "GeneratorExecutable", targets: ["GeneratorExecutable"]),
        .plugin(name: "OpenAPIGeneratorPlugin", targets: ["OpenAPIGeneratorPlugin"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.0.0"),
        .package(url: "https://github.com/mattpolzin/OpenAPIKit.git", exact: "6.0.0"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", exact: "1.19.2"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "602.0.0"),
    ],
    targets: [
        .target(
            name: "OpenAPIGeneratorCore",
            dependencies: [
                .product(name: "OpenAPIKit30", package: "OpenAPIKit"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                "Yams",
            ],
            path: "Sources/OpenAPIGeneratorCore",
            resources: [
                .copy("Resources"),
            ]
        ),
        .executableTarget(
            name: "GeneratorExecutable",
            dependencies: [
                "OpenAPIGeneratorCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/OpenAPIGeneratorCLI"
        ),
        .plugin(
            name: "OpenAPIGeneratorPlugin",
            capability: .command(
                intent: .custom(
                    verb: "generate-openapi",
                    description: "Generate Swift sources from an OpenAPI document."
                ),
                permissions: [
                    .writeToPackageDirectory(reason: "Generated Swift sources are written into the package directory."),
                ]
            ),
            dependencies: [
                .target(name: "GeneratorExecutable"),
            ],
            path: "Plugins/OpenAPIGeneratorPlugin"
        ),
        .testTarget(
            name: "SnapshotTests",
            dependencies: [
                "OpenAPIGeneratorCore",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            path: "Tests",
            exclude: [
                "SnapshotTests/__Snapshots__",
            ],
            sources: [
                "SnapshotTests",
            ],
            resources: [
                .copy("Specs"),
            ]
        ),
    ]
)
