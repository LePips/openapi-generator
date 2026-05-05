import Foundation
import OpenAPIKit30

public struct GenerationPlan {
    public let config: Configuration
    public let document: OpenAPI.Document
    public let outputURL: URL

    public init(
        config: Configuration,
        document: OpenAPI.Document,
        outputURL: URL
    ) {
        self.config = config
        self.document = document
        self.outputURL = outputURL
    }
}

public struct GeneratedFile: Sendable {
    public let relativePath: String
    public let contents: String

    public init(relativePath: String, contents: String) {
        self.relativePath = relativePath
        self.contents = contents
    }
}

public struct GeneratedSourceBundle {
    public let files: [GeneratedFile]
    public let usage: GenerationUsage

    public init(files: [GeneratedFile], usage: GenerationUsage) {
        self.files = files
        self.usage = usage
    }
}

public struct GenerationUsage: Sendable {
    public var usesAnyJSON = false
    public var usesStringCodingKey = false
    public var usesIndirect = false
    public var usesQueryEncoder = false

    public init() {}
}
