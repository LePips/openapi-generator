import Foundation
import OpenAPIKit30
import SwiftParser

public struct HelperFile: Sendable {
    private static let pathsDeclarationPlaceholder = "public enum Paths {}"

    private let emit: Extensions.Emit?
    private let relativePath: @Sendable (GenerationPlan) -> String
    private let replacements: @Sendable (GenerationPlan) -> [String: String]
    private let source: @Sendable (GenerationPlan) throws -> String
    private let shouldEmit: @Sendable (GenerationPlan, GenerationUsage) -> Bool

    private init(
        _ emit: Extensions.Emit,
        templateName: String,
        relativePath: @escaping @Sendable (GenerationPlan) -> String,
        replacements: @escaping @Sendable (GenerationPlan) -> [String: String] = { _ in [:] },
        shouldEmit: @escaping @Sendable (GenerationPlan, GenerationUsage) -> Bool
    ) {
        self.emit = emit
        self.relativePath = relativePath
        self.replacements = replacements
        self.source = { (_: GenerationPlan) throws -> String in
            try Self.template(named: templateName)
        }
        self.shouldEmit = shouldEmit
    }

    private init(
        templateName: String,
        relativePath: @escaping @Sendable (GenerationPlan) -> String,
        shouldEmit: @escaping @Sendable (GenerationPlan, GenerationUsage) -> Bool
    ) {
        self.emit = nil
        self.relativePath = relativePath
        self.replacements = { _ in [:] }
        self.source = { (_: GenerationPlan) throws -> String in
            try Self.template(named: templateName)
        }
        self.shouldEmit = shouldEmit
    }

    private init(
        _ emit: Extensions.Emit,
        relativePath: @escaping @Sendable (GenerationPlan) -> String,
        source: @escaping @Sendable (GenerationPlan) throws -> String,
        shouldEmit: @escaping @Sendable (GenerationPlan, GenerationUsage) -> Bool
    ) {
        self.emit = emit
        self.relativePath = relativePath
        self.replacements = { _ in [:] }
        self.source = source
        self.shouldEmit = shouldEmit
    }

    public static func files(for plan: GenerationPlan, usage: GenerationUsage = .init()) throws -> [GeneratedFile] {
        // Helper templates are copied only when config or generated source usage requires them.
        try all.compactMap { helper in
            guard helper.isEnabled(for: plan), helper.shouldEmit(plan, usage) else { return nil }
            return try helper.file(for: plan)
        }
    }

    private func isEnabled(for plan: GenerationPlan) -> Bool {
        guard let emit else { return true }
        return plan.config.extensions.emit.contains(emit)
    }

    private func file(for plan: GenerationPlan) throws -> GeneratedFile {
        try GeneratedFile(
            relativePath: relativePath(plan),
            contents: render(for: plan)
        )
    }

    private func render(for plan: GenerationPlan) throws -> String {
        var contents = try source(plan)
        for (token, value) in replacements(plan) {
            contents = contents.replacingOccurrences(of: token, with: value)
        }
        contents = Self.addFileHeader(plan.config.fileHeader, to: contents)
        return contents.hasSuffix("\n") ? contents : contents + "\n"
    }

    private static func addFileHeader(_ header: String, to contents: String) -> String {
        let trimmedHeader = header.trimmedForSource
        guard !trimmedHeader.isEmpty else { return contents.trimmedForSource }
        return [trimmedHeader, contents.trimmedForSource].joined(separator: "\n\n")
    }

    private static func template(named name: String) throws -> String {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: "swift",
            subdirectory: "Resources"
        ) else {
            throw GeneratorError("Missing helper file template: \(name).swift")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

private extension HelperFile {
    static let all: [HelperFile] = [
        .anyJSON,
        .stringCodingKey,
        .pathsNamespace,
        .indirect,
        .info,
        .urlQueryEncoder,
    ]

    static let anyJSON = HelperFile(
        .anyJSON,
        templateName: "AnyJSON",
        relativePath: { _ in "Extensions/AnyJSON.swift" },
        shouldEmit: { plan, usage in usage.usesAnyJSON || plan.config.extensions.emit.contains(.anyJSON) }
    )

    static let stringCodingKey = HelperFile(
        .stringCodingKey,
        templateName: "StringCodingKey",
        relativePath: { _ in "Extensions/StringCodingKey.swift" },
        shouldEmit: { plan, usage in
            plan.config.entities.codingStrategy == .stringCodingKey &&
                (usage.usesStringCodingKey || plan.config.extensions.emit.contains(.stringCodingKey))
        }
    )

    static let pathsNamespace = HelperFile(
        .pathsNamespace,
        templateName: "Paths",
        relativePath: { plan in "Extensions/\(plan.config.paths.namespace).swift" },
        replacements: { plan in
            [
                pathsDeclarationPlaceholder: "\(plan.config.access.rawValue) enum \(plan.config.paths.namespace) {}",
            ]
        },
        shouldEmit: { _, _ in true }
    )

    static let indirect = HelperFile(
        .indirect,
        templateName: "Indirect",
        relativePath: { _ in "Extensions/Indirect.swift" },
        shouldEmit: { plan, usage in usage.usesIndirect || plan.config.extensions.emit.contains(.indirect) }
    )

    static let info = HelperFile(
        .info,
        relativePath: { _ in "Extensions/Info.swift" },
        source: { plan in try Self.infoSource(for: plan) },
        shouldEmit: { _, _ in true }
    )

    static let urlQueryEncoder = HelperFile(
        templateName: "URLQueryEncoder",
        relativePath: { _ in "Extensions/URLQueryEncoder.swift" },
        shouldEmit: { _, usage in usage.usesQueryEncoder }
    )
}

private extension HelperFile {
    static func infoSource(for plan: GenerationPlan) throws -> String {
        let info = plan.document.info

        var properties = [
            "public let title: String",
        ]

        var nestedTypes: [String] = []

        if let description = info.description {
            properties.append("public let description: String = \(description.swiftStringLiteral)")
        }

        if let termsOfService = info.termsOfService {
            properties.append("public let termsOfService: URL = \(termsOfService)")
        }

        if let contact = info.contact {
            properties.append("public let contact: Contact = \(contactExpression(contact))")
            nestedTypes.append(contactType(for: contact))
        }

        if let license = info.license {
            properties.append("public let license: License = \(licenseExpression(license))")
            nestedTypes.append(licenseType(for: license))
        }

        properties.append("public let version: Version")
        try nestedTypes.insert(template(named: "Version").trimmedForSource, at: 0)

        return """
        import Foundation

        public struct Info: Sendable {
        \(properties.joined(separator: "\n").indented(count: 1))

        \(nestedTypes.joined(separator: "\n\n").indented(count: 1))
        }
        """
    }

    static func contactExpression(_ contact: OpenAPI.Document.Info.Contact) -> String {
        let arguments = [
            contact.name.map { "name: \($0.swiftStringLiteral)" },
            contact.url.map { "url: \(urlExpression($0))" },
            contact.email.map { "email: \($0.swiftStringLiteral)" },
        ].compactMap(\.self)
        return "Info.Contact(\(arguments.joined(separator: ", ")))"
    }

    static func licenseExpression(_ license: OpenAPI.Document.Info.License) -> String {
        var arguments = ["name: \(license.name.swiftStringLiteral)"]
        if let url = license.url {
            arguments.append("url: \(urlExpression(url))")
        }
        return "Info.License(\(arguments.joined(separator: ", ")))"
    }

    static func contactType(for contact: OpenAPI.Document.Info.Contact) -> String {
        var properties: [String] = []
        var initParameters: [String] = []
        var assignments: [String] = []

        if contact.name != nil {
            properties.append("public let name: String")
            initParameters.append("name: String")
            assignments.append("self.name = name")
        }
        if contact.url != nil {
            properties.append("public let url: URL")
            initParameters.append("url: URL")
            assignments.append("self.url = url")
        }
        if contact.email != nil {
            properties.append("public let email: String")
            initParameters.append("email: String")
            assignments.append("self.email = email")
        }

        let initializer = if initParameters.isEmpty {
            "public init() {}"
        } else {
            """
            public init(
            \(initParameters.map { "\($0.indented(count: 1))" }.joined(separator: ",\n"))
            ) {
            \(assignments.joined(separator: "\n").indented)
            }
            """
        }

        return """
        public struct Contact: Sendable {
        \(properties.joined(separator: "\n").indented)

        \(initializer.indented)
        }
        """
    }

    static func licenseType(for license: OpenAPI.Document.Info.License) -> String {
        var properties = ["public let name: String"]
        var initParameters = ["name: String"]
        var assignments = ["self.name = name"]

        if license.url != nil {
            properties.append("public let url: URL")
            initParameters.append("url: URL")
            assignments.append("self.url = url")
        }

        return """
        public struct License: Sendable {
        \(properties.joined(separator: "\n").indented)

            public init(
        \(initParameters.map { "\($0.indented(count: 2))" }.joined(separator: ",\n"))
            ) {
        \(assignments.joined(separator: "\n").indented(count: 2))
            }
        }
        """
    }

    static func urlExpression(_ url: URL) -> String {
        "URL(string: \(url.absoluteString.swiftStringLiteral))!"
    }
}
