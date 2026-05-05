import Foundation

public extension GenerationPlan {

    func write(_ files: [GeneratedFile]) throws {
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

        var written: Set<String> = []

        for file in files {
            guard written.insert(file.relativePath).inserted else {
                throw GeneratorError("Attempting to write duplicate generated output: \(file.relativePath)")
            }
            let url = outputURL.appending(path: file.relativePath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(file.contents.utf8).write(to: url)
        }
    }
}
