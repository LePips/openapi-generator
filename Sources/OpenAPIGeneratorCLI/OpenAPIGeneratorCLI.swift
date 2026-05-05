import ArgumentParser
import Foundation
import OpenAPIGeneratorCore
import OpenAPIKit30

@main
struct OpenAPIGenerator: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "openapi-generator",
        abstract: "Generate Swift SDK sources from an OpenAPI document.",
        subcommands: [Generate.self],
        defaultSubcommand: Generate.self
    )
}

struct Generate: AsyncParsableCommand {

    @Argument(help: "OpenAPI document in JSON or YAML format.")
    var input: String

    @Option(name: [.customShort("o"), .long], help: "Output directory for generated folders.")
    var output: String = "Sources"

    @Option(name: [.customShort("c"), .long], help: "Configuration in JSON or YAML format.")
    var config: String?

    mutating func run() async throws {
        let currentDirectory = URL(
            filePath: FileManager.default.currentDirectoryPath,
            directoryHint: .isDirectory
        )
        let inputURL = resolve(input, relativeTo: currentDirectory)
        let outputURL = resolve(output, relativeTo: currentDirectory)
        let configURL = config.map { resolve($0, relativeTo: currentDirectory) }

        let config = try configURL.flatMap { url in
            try FileDecoder<Configuration>(url: url).load()
        } ?? Configuration()

        let document = try FileDecoder<OpenAPI.Document>(url: inputURL).load()

        let plan = GenerationPlan(
            config: config,
            document: document,
            outputURL: outputURL
        )

        try plan.write(plan.generatedFiles())
    }

    private func resolve(_ path: String, relativeTo base: URL) -> URL {
        if path.hasPrefix("/") {
            return URL(filePath: path).standardizedFileURL
        }
        return base.appending(path: path).standardizedFileURL
    }
}
