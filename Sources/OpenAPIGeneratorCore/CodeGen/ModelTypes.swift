import Foundation
import OpenAPIKit30

struct StoredDecl {
    let declaration: SwiftDecl
    let fingerprint: String
    var sources: Set<String>
    var emit: Bool
}

final class DeclStore {
    private var entries: [TypeName: StoredDecl] = [:]

    func register(_ declaration: SwiftDecl, source: String, emit: Bool) throws -> StoredDecl {
        let fingerprint = declaration.structuralFingerprint
        if var existing = entries[declaration.name] {
            guard existing.fingerprint == fingerprint else {
                let sources = (existing.sources.union([source])).sorted().joined(separator: ", ")
                throw GeneratorError("Generated type '\(declaration.name.rawValue)' has multiple incompatible shapes: \(sources).")
            }
            existing.sources.insert(source)
            existing.emit = existing.emit || emit
            entries[declaration.name] = existing
            return existing
        }

        let entry = StoredDecl(
            declaration: declaration,
            fingerprint: fingerprint,
            sources: [source],
            emit: emit
        )
        entries[declaration.name] = entry
        return entry
    }

    func promotedEntries(excluding canonicalFileTypes: Set<TypeName>) -> [StoredDecl] {
        entries.values
            .filter { $0.emit && !canonicalFileTypes.contains($0.declaration.name) }
            .sorted {
                $0.declaration.name.rawValue < $1.declaration.name.rawValue
            }
    }
}

protocol SwiftDecl {
    var name: TypeName { get }
}

struct TypeName: Hashable, CustomStringConvertible {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    var description: String {
        rawValue
    }

    func appending(_ suffix: String) -> TypeName {
        TypeName(rawValue + suffix)
    }

    func namespace(_ namespace: String?) -> TypeName {
        guard let namespace, !namespace.isEmpty else { return self }
        return TypeName("\(namespace).\(rawValue)")
    }
}

struct PropertyName: Hashable, CustomStringConvertible {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    var description: String {
        rawValue
    }

    var accessor: String {
        rawValue == "`self`" ? rawValue : rawValue.trimmingCharacters(in: .ticks)
    }

    func asBoolean(acronyms: [String]) -> PropertyName {
        var string = rawValue.trimmingCharacters(in: .ticks)
        let words = string.words
        guard !words.isEmpty, !words.contains(where: booleanExceptions.contains) else { return self }
        let first = words[0]
        if acronyms.contains(first.lowercased()) {
            string.removeFirst(first.count)
            string = first.uppercased() + string
        }
        return PropertyName("is" + string.capitalized)
    }
}

indirect enum SwiftType: Hashable, CustomStringConvertible {
    case builtin(TypeName)
    case userDefined(TypeName)
    case array(SwiftType)
    case dictionary(key: SwiftType = .builtin("String"), value: SwiftType)

    static func builtin(_ value: String) -> SwiftType {
        .builtin(TypeName(value))
    }

    static func userDefined(_ value: String) -> SwiftType {
        .userDefined(TypeName(value))
    }

    var description: String {
        switch self {
        case let .builtin(name), let .userDefined(name):
            name.rawValue
        case let .array(element):
            "[\(element)]"
        case let .dictionary(key, value):
            "[\(key): \(value)]"
        }
    }

    var name: TypeName {
        TypeName(description)
    }

    var isBool: Bool {
        builtinName == "Bool"
    }

    var isString: Bool {
        builtinName == "String"
    }

    var isVoid: Bool {
        builtinName == "Void"
    }

    var isBuiltin: Bool {
        builtinName != nil
    }

    var builtinName: String? {
        if case let .builtin(name) = self { return name.rawValue }
        return nil
    }

    func namespace(_ namespace: String?) -> SwiftType {
        switch self {
        case .builtin:
            self
        case let .userDefined(name):
            .userDefined(name.namespace(namespace))
        case let .array(element):
            .array(element.namespace(namespace))
        case let .dictionary(key, value):
            .dictionary(key: key, value: value.namespace(namespace))
        }
    }
}

struct Property {
    var name: PropertyName
    var type: SwiftType
    var isOptional: Bool
    var key: String
    var explode = true
    var style: OpenAPI.Parameter.SchemaContext.Style?
    var defaultValue: String?
    var metadata: DeclarationMetadata?
    var nested: SwiftDecl?
    var isInlined: Bool?
    var isIndirect = false

    static func == (lhs: Property, rhs: Property) -> Bool {
        lhs.name == rhs.name && lhs.type == rhs.type
    }
}

struct StringEnumDecl: SwiftDecl {
    let name: TypeName
    let cases: [EnumCase]
    let metadata: DeclarationMetadata
}

struct EnumCase {
    let name: String
    let rawValue: String
}

final class EntityDecl: SwiftDecl {
    let name: TypeName
    let kind: EntityKind
    let metadata: DeclarationMetadata
    let isForm: Bool
    var protocols: [String] = []
    var properties: [Property] = []
    var discriminator: Discriminator?
    var isRenderedAsStruct = false

    init(name: TypeName, kind: EntityKind, metadata: DeclarationMetadata, isForm: Bool) {
        self.name = name
        self.kind = kind
        self.metadata = metadata
        self.isForm = isForm
    }

    var nested: [SwiftDecl] {
        properties.compactMap(\.nested)
    }
}

enum EntityKind {
    case object
    case allOf
    case anyOf
    case oneOf
}

struct TypealiasDecl: SwiftDecl {
    let name: TypeName
    let type: SwiftType
    var nested: SwiftDecl?
}

struct InlineFunctionDecl: SwiftDecl {
    let name: TypeName
    let contents: String
}

struct Discriminator {
    let propertyName: String
    let mapping: [String: SwiftType]
}

struct DeclarationMetadata {
    var title: String?
    var description: String?
    var isDeprecated: Bool

    static let empty = DeclarationMetadata(title: nil, description: nil, isDeprecated: false)

    init(title: String?, description: String?, isDeprecated: Bool) {
        self.title = title
        self.description = description
        self.isDeprecated = isDeprecated
    }

    init(_ schema: JSONSchemaContext?) {
        title = schema?.title
        description = schema?.description
        isDeprecated = schema?.deprecated ?? false
    }
}

struct PathOp {
    let name: PropertyName
    let summary: String?
    let description: String?
    let isDeprecated: Bool
    let responseType: SwiftType
    let parameters: [FuncParam]
    let requestExpression: String
    let nested: [SwiftDecl]
}

struct FuncParam {
    let label: String
    let externalName: String
    let type: SwiftType
    let defaultValue: String?
    var isOptional = false

    var signature: String {
        let prefix = externalName == label ? "\(label):" : "\(externalName) \(label):"
        return "\(prefix) \(type)\(isOptional ? "?" : "")\(defaultValue.map { " = \($0)" } ?? "")"
    }
}

struct PathParam {
    let key: String
    let name: PropertyName
    let type: TypeName
}

struct BodyUse {
    var type: SwiftType
    var nested: SwiftDecl?
    var isOptional: Bool
}

struct MakeContext {
    var parents: [EntityDecl] = []
    var namespace: String?
    var isFormEncoding = false

    init(namespace: String? = nil) {
        self.namespace = namespace
    }
}

public struct GeneratorError: Error, CustomStringConvertible, LocalizedError {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String {
        message
    }

    public var errorDescription: String? {
        message
    }
}

private extension SwiftDecl {
    var structuralFingerprint: String {
        switch self {
        case let declaration as EntityDecl:
            return declaration.structuralFingerprint
        case let declaration as StringEnumDecl:
            let cases = declaration.cases.map { "\($0.name)=\($0.rawValue)" }.joined(separator: ",")
            return "enum|\(declaration.name.rawValue)|\(cases)"
        case let declaration as TypealiasDecl:
            return "typealias|\(declaration.name.rawValue)|\(declaration.type)|\(declaration.nested?.structuralFingerprint ?? "")"
        case let declaration as InlineFunctionDecl:
            return "function|\(declaration.name.rawValue)|\(declaration.contents)"
        default:
            return "unknown|\(name.rawValue)"
        }
    }
}

private extension EntityDecl {
    var structuralFingerprint: String {
        let properties = properties
            .map(\.structuralFingerprint)
            .joined(separator: ";")
        let discriminator = discriminator
            .map { "\($0.propertyName)|\($0.mapping.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ","))" } ??
            ""
        return [
            "entity",
            name.rawValue,
            "\(kind)",
            "form:\(isForm)",
            "rendered:\(isRenderedAsStruct)",
            "protocols:\(protocols.joined(separator: ","))",
            "properties:\(properties)",
            "discriminator:\(discriminator)",
        ].joined(separator: "|")
    }
}

private extension Property {
    var structuralFingerprint: String {
        [
            name.rawValue,
            "\(type)",
            "optional:\(isOptional)",
            "key:\(key)",
            "explode:\(explode)",
            "style:\(style.map(String.init(describing:)) ?? "")",
            "default:\(defaultValue ?? "")",
            "indirect:\(isIndirect)",
            "nested:\(nested?.structuralFingerprint ?? "")",
        ].joined(separator: "|")
    }
}
