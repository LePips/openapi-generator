#!/usr/bin/env swift

import Foundation

struct Schema {
    let name: String
    let url: URL
}

let specExtensions = Set(["json", "yaml", "yml"])

enum BuildMode: String, CaseIterable {
    case debug
    case release

    var swiftBuildArguments: [String] {
        switch self {
        case .debug:
            ["build", "--product", "openapi-generator"]
        case .release:
            ["build", "-c", "release", "--product", "openapi-generator"]
        }
    }

    var showBinPathArguments: [String] {
        switch self {
        case .debug:
            ["build", "--show-bin-path"]
        case .release:
            ["build", "-c", "release", "--show-bin-path"]
        }
    }
}

enum PathGeneration: String, CaseIterable {
    case operations
    case paths

    var configContents: String {
        let style = switch self {
        case .operations:
            "operations"
        case .paths:
            "rest"
        }
        return """
        generate:
          - paths
        paths:
          style: \(style)
        """
    }
}

struct ProcessResult {
    let status: Int32
    let output: String
}

struct BenchmarkResult {
    let schema: Schema
    let mode: BuildMode
    let generation: PathGeneration
    let elapsed: TimeInterval
    let fileCount: Int?
    let byteCount: UInt64?
    let errorOutput: String?

    var succeeded: Bool {
        errorOutput == nil
    }
}

let fileManager = FileManager.default
let rootURL = URL(filePath: fileManager.currentDirectoryPath, directoryHint: .isDirectory)
    .standardizedFileURL

let packageURL = rootURL.appending(path: "Package.swift")
guard fileManager.fileExists(atPath: packageURL.path) else {
    fputs("error: run this script from the openapi-generator package root\n", stderr)
    exit(2)
}

let sourcesURL = rootURL.appending(path: "Sources", directoryHint: .isDirectory)
guard fileManager.fileExists(atPath: sourcesURL.path) else {
    fputs("error: run this script from the openapi-generator package root\n", stderr)
    exit(2)
}

let specsURL = rootURL
    .appending(path: "Scripts", directoryHint: .isDirectory)
    .appending(path: "Specs", directoryHint: .isDirectory)

guard fileManager.fileExists(atPath: specsURL.path) else {
    fputs("error: missing specs directory at \(specsURL.path)\n", stderr)
    exit(2)
}

let outputRootURL = rootURL
    .appending(path: ".build", directoryHint: .isDirectory)
    .appending(path: "performance-generation", directoryHint: .isDirectory)

do {
    let schemas = try discoverSchemas(at: specsURL)
    guard !schemas.isEmpty else {
        fputs("error: no .json, .yaml, or .yml specs found in \(specsURL.path)\n", stderr)
        exit(2)
    }

    let executables = try Dictionary(uniqueKeysWithValues: BuildMode.allCases.map { mode in
        print("Building \(mode.rawValue)...")
        let build = try run("/usr/bin/swift", arguments: mode.swiftBuildArguments, currentDirectory: rootURL)
        guard build.status == 0 else {
            throw ScriptError.commandFailed("swift \(mode.swiftBuildArguments.joined(separator: " "))", build.output)
        }

        let binPath = try run("/usr/bin/swift", arguments: mode.showBinPathArguments, currentDirectory: rootURL)
        guard binPath.status == 0 else {
            throw ScriptError.commandFailed("swift \(mode.showBinPathArguments.joined(separator: " "))", binPath.output)
        }

        let executableURL = URL(filePath: binPath.output.trimmingCharacters(in: .whitespacesAndNewlines))
            .appending(path: "openapi-generator")
        guard fileManager.isExecutableFile(atPath: executableURL.path) else {
            throw ScriptError.message("expected executable at \(executableURL.path)")
        }

        return (mode, executableURL)
    })

    var results: [BenchmarkResult] = []
    let configURLs = try Dictionary(uniqueKeysWithValues: PathGeneration.allCases.map { generation in
        let configURL = outputRootURL
            .appending(path: "configs", directoryHint: .isDirectory)
            .appending(path: "\(generation.rawValue).yml")
        try fileManager.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(generation.configContents.utf8).write(to: configURL)
        return (generation, configURL)
    })

    for schema in schemas {
        for mode in BuildMode.allCases {
            for generation in PathGeneration.allCases {
                let outputURL = outputRootURL
                    .appending(path: mode.rawValue, directoryHint: .isDirectory)
                    .appending(path: generation.rawValue, directoryHint: .isDirectory)
                    .appending(path: schema.nameWithoutExtension, directoryHint: .isDirectory)

                try? fileManager.removeItem(at: outputURL)

                let start = Date()
                let generated = try run(
                    executables[mode]!.path,
                    arguments: [
                        "generate",
                        schema.url.path,
                        "--config",
                        configURLs[generation]!.path,
                        "--output",
                        outputURL.path,
                    ],
                    currentDirectory: rootURL
                )
                let elapsed = Date().timeIntervalSince(start)

                if generated.status == 0 {
                    let size = try directorySize(at: outputURL)
                    results.append(BenchmarkResult(
                        schema: schema,
                        mode: mode,
                        generation: generation,
                        elapsed: elapsed,
                        fileCount: size.fileCount,
                        byteCount: size.byteCount,
                        errorOutput: nil
                    ))
                } else {
                    results.append(BenchmarkResult(
                        schema: schema,
                        mode: mode,
                        generation: generation,
                        elapsed: elapsed,
                        fileCount: nil,
                        byteCount: nil,
                        errorOutput: generated.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    ))
                }
            }
        }
    }

    print("")
    printTable(results)
    printFailures(results)

    exit(results.allSatisfy(\.succeeded) ? 0 : 1)
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}

func run(_ executable: String, arguments: [String], currentDirectory: URL) throws -> ProcessResult {
    let process = Process()
    process.executableURL = URL(filePath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = currentDirectory

    let outputURL = fileManager.temporaryDirectory
        .appending(path: "openapi-generator-benchmark-\(UUID().uuidString).log")
    fileManager.createFile(atPath: outputURL.path, contents: nil)
    let outputHandle = try FileHandle(forWritingTo: outputURL)
    defer {
        try? fileManager.removeItem(at: outputURL)
    }

    process.standardOutput = outputHandle
    process.standardError = outputHandle

    try process.run()
    process.waitUntilExit()
    try outputHandle.close()

    let data = try Data(contentsOf: outputURL)
    let output = String(data: data, encoding: .utf8) ?? ""
    return ProcessResult(status: process.terminationStatus, output: output)
}

func discoverSchemas(at url: URL) throws -> [Schema] {
    guard let enumerator = fileManager.enumerator(
        at: url,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        throw ScriptError.message("unable to enumerate \(url.path)")
    }

    var schemaURLs: [URL] = []
    for case let schemaURL as URL in enumerator {
        let values = try schemaURL.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else { continue }
        guard specExtensions.contains(schemaURL.pathExtension.lowercased()) else { continue }
        schemaURLs.append(schemaURL)
    }

    return schemaURLs
        .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        .map { Schema(name: $0.lastPathComponent, url: $0) }
}

func directorySize(at url: URL) throws -> (fileCount: Int, byteCount: UInt64) {
    guard let enumerator = fileManager.enumerator(
        at: url,
        includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
        options: [.skipsHiddenFiles]
    ) else {
        throw ScriptError.message("unable to enumerate \(url.path)")
    }

    var fileCount = 0
    var byteCount: UInt64 = 0

    for case let fileURL as URL in enumerator {
        let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { continue }
        fileCount += 1
        byteCount += UInt64(values.fileSize ?? 0)
    }

    return (fileCount, byteCount)
}

func printTable(_ results: [BenchmarkResult]) {
    let rows = results.map { result in
        [
            result.schema.name,
            result.mode.rawValue,
            result.generation.rawValue,
            result.succeeded ? "ok" : "failed",
            String(format: "%.2f", result.elapsed),
            result.fileCount.map(String.init) ?? "n/a",
            result.byteCount.map(formatByteCount) ?? "n/a",
        ]
    }

    let header = ["schema", "mode", "generation", "status", "time(s)", "files", "size"]
    let widths = columnWidths(header: header, rows: rows)

    print(formatRow(header, widths: widths))
    for row in rows {
        print(formatRow(row, widths: widths))
    }
}

func printFailures(_ results: [BenchmarkResult]) {
    let failures = results.filter { !$0.succeeded }
    guard !failures.isEmpty else { return }

    print("")
    print("Failures:")
    for failure in failures {
        print("[\(failure.schema.name), \(failure.mode.rawValue), \(failure.generation.rawValue)]")
        print(failure.errorOutput?.isEmpty == false ? failure.errorOutput! : "No error output captured.")
    }
}

func columnWidths(header: [String], rows: [[String]]) -> [Int] {
    header.indices.map { index in
        ([header[index]] + rows.map { $0[index] }).map(\.count).max() ?? 0
    }
}

func formatRow(_ columns: [String], widths: [Int]) -> String {
    zip(columns, widths)
        .map { column, width in column.padding(toLength: width, withPad: " ", startingAt: 0) }
        .joined(separator: "  ")
}

func formatByteCount(_ bytes: UInt64) -> String {
    let units = ["B", "KiB", "MiB", "GiB"]
    var value = Double(bytes)
    var unitIndex = 0

    while value >= 1024, unitIndex < units.count - 1 {
        value /= 1024
        unitIndex += 1
    }

    if unitIndex == 0 {
        return "\(bytes) B"
    }

    return String(format: "%.2f %@", value, units[unitIndex])
}

extension Schema {
    var nameWithoutExtension: String {
        url.deletingPathExtension().lastPathComponent
    }
}

enum ScriptError: Error, CustomStringConvertible {
    case commandFailed(String, String)
    case message(String)

    var description: String {
        switch self {
        case let .commandFailed(command, output):
            let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedOutput.isEmpty {
                return "\(command) failed"
            }
            return "\(command) failed\n\(trimmedOutput)"
        case let .message(message):
            return message
        }
    }
}
