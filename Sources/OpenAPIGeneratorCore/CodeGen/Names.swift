import Foundation

final class NameResolver {
    let config: Configuration
    private let processor: NameProcessor
    private var types: [String: TypeName] = [:]
    private var properties: [String: PropertyName] = [:]

    init(config: Configuration) {
        self.config = config
        processor = NameProcessor(acronyms: config.acronyms)
    }

    func type(_ rawValue: String) -> TypeName {
        if let cached = types[rawValue] {
            return cached
        }
        let value = TypeName(processor.process(rawValue, isProperty: false))
        types[rawValue] = value
        return value
    }

    func property(_ rawValue: String) -> PropertyName {
        if let cached = properties[rawValue] {
            return cached
        }
        let value = PropertyName(processor.process(rawValue, isProperty: true))
        properties[rawValue] = value
        return value
    }
}

func template(_ rawValue: String, _ parameter: String) -> String {
    rawValue.replacingOccurrences(of: "%0", with: parameter)
}

func sanitizeEnumCaseName(_ string: String) -> String {
    if string.count == 1,
       !(string.unicodeScalars.count == 1 && Character(string).isNumber),
       string.unicodeScalars.allSatisfy(\.properties.isEmoji)
    {
        return string.unicodeScalars.compactMap(\.properties.name).joined(separator: "")
    }
    return string
}

func orderedProtocols(_ protocols: Set<String>) -> [String] {
    let preferred = [
        "Codable",
        "Decodable",
        "Encodable",
        "CaseIterable",
        "Hashable",
        "Identifiable",
        "Sendable"
    ]
    return preferred.filter(protocols.contains) + protocols.subtracting(preferred).sorted()
}

let booleanExceptions = Set(
    [
        "is",
        "has",
        "have",
        "allow",
        "allows",
        "enable",
        "enables",
        "require",
        "requires",
        "delete",
        "deletes",
        "can",
        "should",
        "use",
        "uses",
        "contain",
        "contains",
        "dismiss",
        "dismisses",
        "respond",
        "responds",
        "exclude",
        "excludes",
        "lock",
        "locks",
        "was",
        "were",
        "enforce",
        "enforces",
        "resolve",
        "resolves",
    ]
)

let keywords = Set(
    [
        "func",
        "public",
        "private",
        "open",
        "fileprivate",
        "internal",
        "default",
        "import",
        "init",
        "deinit",
        "typealias",
        "let",
        "var",
        "in",
        "return",
        "for",
        "switch",
        "where",
        "associatedtype",
        "guard",
        "enum",
        "struct",
        "class",
        "protocol",
        "extension",
        "if",
        "else",
        "self",
        "none",
        "throw",
        "throws",
        "rethrows",
        "inout",
        "operator",
        "static",
        "subscript",
        "case",
        "break",
        "continue",
        "defer",
        "do",
        "fallthrough",
        "repeat",
        "while",
        "as",
        "some",
        "super",
        "catch",
        "false",
        "true",
        "is",
        "nil",
        "try",
    ]
)

let capitalizedKeywords = Set(
    [
        "Self",
        "Type",
        "Protocol",
        "Any",
        "AnyObject"
    ]
)

let replacements = [
    "=": "equal", "!=": "notEqual", ">=": "greaterThanOrEqualTo", "<=": "lessThanOrEqualTo",
    ">": "greaterThan", "<": "lessThan", "$": "dollar", "%": "percent", "#": "hash",
    "@": "alpha", "&": "and", "+": "plus", "\"": "backslash", "/": "slash",
    "~": "tilda", "~=": "tildaEqual",
]

let badCharacters = CharacterSet.alphanumerics.inverted
