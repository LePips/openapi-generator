import Foundation

extension GenerationPlan {
    public func generatedFiles() throws -> [GeneratedFile] {
        let shouldGeneratePackage = config.generate.contains(.package)
        if shouldGeneratePackage, config.module.isEmpty {
            throw GeneratorError("You must specify a non-empty value for `module` when generating a package.")
        }

        let generated = try CodeGen(plan: self).generate()
        let sourceFiles = try generated.files + HelperFile.files(for: self, usage: generated.usage)

        guard shouldGeneratePackage else {
            return sourceFiles
        }

        return [packageFile()] + sourceFiles.map { file in
            GeneratedFile(relativePath: "Sources/\(file.relativePath)", contents: file.contents)
        }
    }

    private func packageFile() -> GeneratedFile {
        let manifest = makePackageFile()
        return GeneratedFile(relativePath: "Package.swift", contents: manifest.hasSuffix("\n") ? manifest : manifest + "\n")
    }

    private func makePackageFile() -> String {
        """
        // swift-tools-version:6.1

        import PackageDescription

        let package = Package(
            name: \(config.module.swiftStringLiteral),
            platforms: [.iOS(.v16), .macOS(.v13)],
            products: [
                .library(name: \(config.module.swiftStringLiteral), targets: [\(config.module.swiftStringLiteral)]),
            ],
            dependencies: [
                .package(url: "https://github.com/kean/Get", from: "2.1.0"),
            ],
            targets: [
                .target(
                    name: \(config.module.swiftStringLiteral),
                    dependencies: [
                        .product(name: "Get", package: "Get"),
                    ],
                    path: "Sources"
                )
            ]
        )
        """
    }
}
