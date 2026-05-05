import Foundation
import PackagePlugin

@main
struct OpenAPIGeneratorPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        var arguments = arguments

        if arguments.isEmpty || arguments.contains("--help") || arguments.contains("-h") {
            print("""
            Usage:
              swift package plugin --allow-writing-to-package-directory generate-openapi <input> [--config <config>] [--output <output>]
            """)
            return
        }

        let tool = try context.tool(named: "GeneratorExecutable")

        let process = Process()
        process.executableURL = tool.url
        process.arguments = arguments
        process.currentDirectoryURL = context.package.directoryURL
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        try process.run()
        process.waitUntilExit()

        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw PluginError.generationFailed(process.terminationStatus)
        }
    }
}

enum PluginError: Error, CustomStringConvertible {
    case generationFailed(Int32)

    var description: String {
        switch self {
        case let .generationFailed(status):
            "OpenAPI generation failed with exit code \(status)."
        }
    }
}
