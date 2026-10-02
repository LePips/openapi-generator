import Foundation
import OpenAPIGeneratorCore
import OpenAPIKit30
import Testing

struct DiscriminatorDecodingTests {
    @Test(arguments: ["Type", "type", "class", "event-kind"], [false, true])
    func `discriminator decoding`(propertyName: String, useCodingKeys: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fixtureURL = try #require(Bundle.module.resourceURL?.appending(path: "Specs/discriminator-type.yaml"))
        let schema = try String(contentsOf: fixtureURL, encoding: .utf8)
            .replacingOccurrences(of: "Type", with: propertyName)
        let specURL = directory.appending(path: "spec.yaml")
        try schema.write(to: specURL, atomically: true, encoding: .utf8)

        var config = Configuration()
        config.generate = [.entities]
        config.extensions.emit = useCodingKeys ? [] : [.stringCodingKey]
        if useCodingKeys {
            config.entities.codingStrategy = .codingKeys
        }
        let plan = try GenerationPlan(
            config: config,
            document: FileDecoder<OpenAPI.Document>(url: specURL).load(),
            outputURL: directory
        )
        let files = try plan.generatedFiles()
        try plan.write(files)

        // Compile and execute the generated models: a snapshot alone cannot detect
        // a synthesized Decodable implementation reading the wrong JSON key.
        let main = #"""
        import Foundation

        func check(_ condition: Bool) throws {
            if !condition { throw NSError(domain: "DiscriminatorRegression", code: 1) }
        }

        func verify() throws {
            let decoder = JSONDecoder()
            let catJSON = Data(#"{"\#(propertyName)":"cat","meows":true}"#.utf8)
            let cat = try decoder.decode(Payload.self, from: catJSON)
            guard case let .cat(value) = cat else {
                throw NSError(domain: "ExpectedCat", code: 1)
            }
            try check(value.isMeows)
            let encoded = try JSONEncoder().encode(cat)
            let object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
            try check(object["\#(propertyName)"] as? String == "cat")
            try check(object["_Type"] == nil)

            let dogJSON = Data(#"{"\#(propertyName)":"dog","barks":true}"#.utf8)
            guard case let .dog(dog) = try decoder.decode(Payload.self, from: dogJSON) else {
                throw NSError(domain: "ExpectedDog", code: 1)
            }
            try check(dog.isBarks)

            do {
                _ = try decoder.decode(Payload.self, from: Data(#"{"\#(propertyName)":"unknown"}"#.utf8))
                throw NSError(domain: "ExpectedDataCorrupted", code: 1)
            } catch DecodingError.dataCorrupted { }

            do {
                _ = try decoder.decode(Payload.self, from: Data(#"{"_Type":"cat","meows":true}"#.utf8))
                throw NSError(domain: "ExpectedKeyNotFound", code: 1)
            } catch DecodingError.keyNotFound(let key, _) {
                try check(key.stringValue == "\#(propertyName)")
            }
        }

        do {
            try verify()
        } catch {
            print(error)
            exit(1)
        }
        """#
        let mainURL = directory.appending(path: "main.swift")
        try main.write(to: mainURL, atomically: true, encoding: .utf8)
        let executableURL = directory.appending(path: "verify")
        let sourcePaths = files.filter { $0.relativePath.hasSuffix(".swift") }
            .map { directory.appending(path: $0.relativePath).path }
        try run("/usr/bin/env", arguments: ["swiftc"] + sourcePaths + [mainURL.path, "-o", executableURL.path])
        try run(executableURL.path, arguments: [])
    }

    private func run(_ executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0, "\(String(decoding: output, as: UTF8.self))")
    }
}
