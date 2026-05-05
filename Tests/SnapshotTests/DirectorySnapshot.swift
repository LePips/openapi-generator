import Foundation
import OpenAPIGeneratorCore
import OpenAPIKit30
@_spi(Internals) @preconcurrency import SnapshotTesting

enum DirectorySnapshot {
    static func assert(
        named name: String,
        spec: String,
        config: Configuration = .init(),
        fileFilter: [String]? = nil,
        fileID _: StaticString = #fileID,
        filePath: StaticString = #filePath,
        testName: String = #function,
        line _: UInt = #line,
        column _: UInt = #column
    ) throws {
        let generatedURL = try generate(spec: spec, config: config, fileFilter: fileFilter)
        defer {
            try? FileManager.default.removeItem(at: generatedURL.deletingLastPathComponent())
        }

        let snapshotURL = URL.snapshotDirectory(filePath: filePath, name: name)
        let record = SnapshotTestingConfiguration.current?.record ?? _record

        func recordSnapshot(_ message: String) throws -> Never {
            try snapshotURL.replaceDirectory(with: generatedURL)
            throw SnapshotFailure(message)
        }

        switch (record, snapshotURL.exists) {
        case (.all, _):
            try recordSnapshot("Record mode is on. Recorded generated directory snapshot at \(snapshotURL.path).")
        case (.never, false):
            throw SnapshotFailure("No generated directory snapshot exists at \(snapshotURL.path), and recording is disabled.")
        case (_, false):
            try recordSnapshot(
                "No generated directory snapshot existed. Recorded \(name) at \(snapshotURL.path). Re-run \(testName) to verify it."
            )
        default:
            break
        }

        let strategy = Snapshotting<URL, GeneratedDirectory>.generatedDirectory
        let reference = try GeneratedDirectory(rootURL: snapshotURL)
        let generated = try strategy.snapshot(generatedURL).value()
        guard let (difference, _) = strategy.diffing.diffV2(reference, generated) else {
            return
        }

        let failedSnapshotURL = URL.failedSnapshotDirectory(filePath: filePath, name: name)
        try failedSnapshotURL.replaceDirectory(with: generatedURL)

        let diffMessage = (SnapshotTestingConfiguration.current?.diffTool ?? _diffTool)(
            currentFilePath: snapshotURL.path,
            failedFilePath: failedSnapshotURL.path
        )

        if record == .failed {
            try snapshotURL.replaceDirectory(with: generatedURL)
            throw SnapshotFailure(
                """
                Generated directory snapshot "\(name)" does not match reference. A new snapshot was automatically recorded.

                \(diffMessage)

                \(difference)
                """
            )
        }

        throw SnapshotFailure(
            """
            Generated directory snapshot "\(name)" does not match reference.

            \(diffMessage)

            \(difference)
            """
        )
    }

    private static func generate(
        spec: String,
        config: Configuration,
        fileFilter: [String]? = nil
    ) throws -> URL {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)

        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )

        let outputURL = temporaryDirectory.appending(path: "Output", directoryHint: .isDirectory)
        let specURL = Bundle.module
            .resourceURL!
            .appending(path: "Specs", directoryHint: .isDirectory)
            .appending(path: spec)

        let document = try FileDecoder<OpenAPI.Document>(url: specURL).load()
        let plan = GenerationPlan(
            config: config,
            document: document,
            outputURL: outputURL
        )

        let files = try plan.generatedFiles()
            .filter { file in
                guard let fileFilter else { return true }
                return fileFilter.contains(where: { $0 == file.relativePath })
            }

        try plan.write(files)

        return outputURL
    }
}

private struct GeneratedDirectory: Equatable {
    var entries: [String: Entry] = [:]
    var errorDescription: String?

    var entryNames: Set<String> {
        Set(entries.keys)
    }

    init(entries: [String: Entry], errorDescription: String? = nil) {
        self.entries = entries
        self.errorDescription = errorDescription
    }

    init(rootURL: URL) throws {
        let rootURL = rootURL.resolvingSymlinksInPath()
        let rootComponents = rootURL.pathComponents
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw SnapshotFailure("Unable to enumerate generated directory at \(rootURL.path).")
        }

        for case let url as URL in enumerator {
            let relativePath = url
                .resolvingSymlinksInPath()
                .pathComponents
                .dropFirst(rootComponents.count)
                .joined(separator: "/")
            let name = url.lastPathComponent
            if name == "Package.resolved" {
                continue
            }

            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values.isDirectory == true {
                entries[relativePath] = .directory
            } else if values.isRegularFile == true {
                entries[relativePath] = try .file(Data(contentsOf: url))
            }
        }
    }

    var manifest: String {
        if let errorDescription {
            return "error \(errorDescription)"
        }

        return entries.keys.sorted().map { name in
            switch entries[name] {
            case .directory:
                "directory \(name)"
            case let .file(data):
                "file \(name) \(data.count) bytes"
            case nil:
                ""
            }
        }
        .joined(separator: "\n")
    }

    enum Entry: Equatable {
        case directory
        case file(Data)
    }
}

private extension Snapshotting where Value == URL, Format == GeneratedDirectory {
    static let generatedDirectory = Snapshotting(
        pathExtension: nil,
        diffing: .generatedDirectory
    ) { url in
        do {
            return try GeneratedDirectory(rootURL: url)
        } catch {
            return GeneratedDirectory(entries: [:], errorDescription: error.localizedDescription)
        }
    }
}

private extension Diffing where Value == GeneratedDirectory {
    static let generatedDirectory = Diffing.diff(
        toData: { Data($0.manifest.utf8) },
        fromData: { _ in GeneratedDirectory(entries: [:]) }
    ) { reference, generated in
        let added = generated.entryNames.subtracting(reference.entryNames).sorted()
        let removed = reference.entryNames.subtracting(generated.entryNames).sorted()
        let common = reference.entryNames.intersection(generated.entryNames).sorted()

        var changed: [String] = []
        var contentDiffs: [String] = []
        for name in common {
            guard reference.entries[name] != generated.entries[name] else { continue }
            changed.append(name)

            guard case let .file(referenceData) = reference.entries[name],
                  case let .file(generatedData) = generated.entries[name]
            else {
                continue
            }

            guard let referenceText = String(data: referenceData, encoding: .utf8),
                  let generatedText = String(data: generatedData, encoding: .utf8)
            else {
                contentDiffs.append("Diff for \(name):\n  Binary contents differ.")
                continue
            }

            let textDifference = Diffing<String>.lines.diffV2(referenceText, generatedText)?.0
                ?? "Text contents differ."
            contentDiffs.append("Diff for \(name):\n\(indent(textDifference))")
        }

        guard !added.isEmpty || !removed.isEmpty || !changed.isEmpty else {
            return nil
        }

        var lines: [String] = []
        if !added.isEmpty {
            lines.append("Added:")
            lines.append(contentsOf: added.map { "  + \($0)" })
        }
        if !removed.isEmpty {
            lines.append("Removed:")
            lines.append(contentsOf: removed.map { "  - \($0)" })
        }
        if !changed.isEmpty {
            lines.append("Changed:")
            lines.append(contentsOf: changed.map { "  * \($0)" })
        }
        if !contentDiffs.isEmpty {
            lines.append("")
            lines.append(contentsOf: contentDiffs)
        }

        let failure = lines.joined(separator: "\n")
        return (failure, [])
    }
}

private extension Async where Value == GeneratedDirectory {
    func value() throws -> GeneratedDirectory {
        let semaphore = DispatchSemaphore(value: 0)
        var value: GeneratedDirectory?
        run {
            value = $0
            semaphore.signal()
        }
        semaphore.wait()

        guard let value else {
            throw SnapshotFailure("Unable to snapshot generated directory.")
        }
        if let errorDescription = value.errorDescription {
            throw SnapshotFailure(errorDescription)
        }
        return value
    }
}

private func indent(_ string: String) -> String {
    string
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { "  \($0)" }
        .joined(separator: "\n")
}

private struct SnapshotFailure: Error, CustomStringConvertible, LocalizedError {
    var description: String
    var errorDescription: String? {
        description
    }

    init(_ description: String) {
        self.description = description
    }
}

private extension URL {
    static func snapshotDirectory(filePath: StaticString, name: String) -> URL {
        let fileURL = URL(filePath: "\(filePath)", directoryHint: .notDirectory)
        return fileURL
            .deletingLastPathComponent()
            .appending(path: "__Snapshots__", directoryHint: .isDirectory)
            .appending(path: fileURL.deletingPathExtension().lastPathComponent, directoryHint: .isDirectory)
            .appending(path: name.sanitizedPathComponent, directoryHint: .isDirectory)
    }

    static func failedSnapshotDirectory(filePath: StaticString, name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "SnapshotTests", directoryHint: .isDirectory)
            .appending(path: URL(filePath: "\(filePath)").deletingPathExtension().lastPathComponent, directoryHint: .isDirectory)
            .appending(path: name.sanitizedPathComponent, directoryHint: .isDirectory)
    }

    var exists: Bool {
        FileManager.default.fileExists(atPath: path)
    }

    func replaceDirectory(with sourceURL: URL) throws {
        let fileManager = FileManager.default
        if exists {
            try fileManager.removeItem(at: self)
        }
        try fileManager.createDirectory(at: deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: sourceURL, to: self)
    }
}

private extension String {
    var sanitizedPathComponent: String {
        replacingOccurrences(of: "\\W+", with: "-", options: .regularExpression)
            .replacingOccurrences(of: "^-|-$", with: "", options: .regularExpression)
    }
}
