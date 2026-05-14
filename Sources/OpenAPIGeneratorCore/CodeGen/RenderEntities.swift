import Foundation

extension CodeGen {
    func renderStringEnum(_ declaration: StringEnumDecl) -> String {
        let protocols = orderedProtocols(plan.config.entities.enumConformances)
        let inheritance = ([SwiftType.builtin("String").description] + protocols).joined(separator: ", ")
        let cases = declaration.cases.map { enumCase(name: $0.name, value: $0.rawValue) }.joined(separator: "\n")
        return comments(for: declaration.metadata, name: declaration.name.rawValue) + """
        \(access)enum \(declaration.name.rawValue): \(inheritance) {
        \(cases.indented)
        }
        """
    }

    func renderEntity(_ declaration: EntityDecl) throws -> String {
        state.usage.usesStringCodingKey = state.usage.usesStringCodingKey || (
            plan.config.entities.codingStrategy == .stringCodingKey &&
                !declaration.isForm &&
                declaration.kind != .oneOf &&
                !declaration.properties.isEmpty
        )

        let resolvedType = resolveType(for: declaration)
        let isReadOnly = !plan.config.entities.mutableProperties.contains(resolvedType == "struct" ? .structs : .classes)
        var body: [String] = []
        switch declaration.kind {
        case .object, .allOf, .anyOf:
            body.append(declaration.properties.map { renderProperty($0, isReadOnly: isReadOnly) }.joined(separator: "\n"))
            body += try declaration.nested.map(render)
            if plan.config.entities.memberwiseInit {
                body.append(renderInitializer(properties: declaration.properties))
            }
        case .oneOf:
            body.append(declaration.properties.map { "case \($0.name.rawValue)(\($0.type))" }.joined(separator: "\n"))
            body += try declaration.nested.map(render)
        }

        if declaration.isForm {
            body.append(renderAsQuery(properties: declaration.properties))
        } else {
            switch declaration.kind {
            case .object:
                let includeDecode = declaration.protocols
                    .contains(where: { $0 == "Codable" || $0 == "Decodable" }) && !declaration.properties.isEmpty
                let includeEncode = declaration.protocols
                    .contains(where: { $0 == "Codable" || $0 == "Encodable" }) && !declaration.properties.isEmpty
                if plan.config.entities.codingStrategy == .codingKeys, includeDecode || includeEncode {
                    body.append(renderCodingKeys(properties: declaration.properties))
                }
                if includeDecode {
                    body.append(renderDecode(properties: declaration.properties))
                }
                if includeEncode {
                    body.append(renderEncode(properties: declaration.properties))
                }
            case .allOf:
                if plan.config.entities.codingStrategy == .codingKeys, !declaration.properties.isEmpty {
                    body.append(renderCodingKeys(properties: declaration.properties))
                }
                body.append(renderDecode(properties: declaration.properties))
                body.append(renderEncode(properties: declaration.properties))
            case .anyOf:
                body.append(renderAnyOfDecode(properties: declaration.properties))
                body.append(renderAnyOfEncode(properties: declaration.properties))
            case .oneOf:
                if let discriminator = declaration.discriminator {
                    body.append(renderOneOfDecodeWithDiscriminator(properties: declaration.properties, discriminator: discriminator))
                } else {
                    body.append(renderOneOfDecode(properties: declaration.properties))
                }
                body.append(renderOneOfEncode(properties: declaration.properties))
            }
        }

        let header: String
        let inheritance = declaration.protocols.isEmpty ? "" : ": \(declaration.protocols.joined(separator: ", "))"
        switch resolvedType {
        case "enum":
            header = "\(access)enum \(declaration.name.rawValue)\(inheritance)"
        case "class":
            header = "\(access)class \(declaration.name.rawValue)\(inheritance)"
        case "final class":
            header = "\(access)final class \(declaration.name.rawValue)\(inheritance)"
        default:
            header = "\(access)struct \(declaration.name.rawValue)\(inheritance)"
        }

        return comments(for: declaration.metadata, name: declaration.name.rawValue) + """
        \(header) {
        \(body.filter { !$0.isEmpty }.joined(separator: "\n\n").indented)
        }
        """
    }

    func renderTypealias(_ declaration: TypealiasDecl) throws -> String {
        let alias = "\(access)typealias \(declaration.name.rawValue) = \(declaration.type)"
        if let nested = declaration.nested {
            return try alias + "\n\n" + render(nested)
        }
        return alias
    }

    func renderProperty(_ property: Property, isReadOnly: Bool) -> String {
        let optional = property.isOptional && property.defaultValue == nil ? "?" : ""
        let wrapper = property.isIndirect ? "@Indirect\n" : ""
        let commentBlock = property.metadata.map { comments(for: $0, name: property.name.rawValue) } ?? ""
        return commentBlock + "\(wrapper)\(access)\(isReadOnly ? "let" : "var") \(property.name.rawValue): \(property.type)\(optional)"
    }

    func renderInitializer(properties: [Property]) -> String {
        guard !properties.isEmpty else { return "\(access)init() {}" }
        let parameters = properties.map { "\($0.name.rawValue): \($0.type)\($0.isOptional ? "? = nil" : "")" }.joined(separator: ", ")
        let assignments = properties.map {
            let defaultValue = ($0.isOptional && $0.defaultValue != nil) ? " ?? \($0.defaultValue!)" : ""
            return "self.\($0.name.accessor) = \($0.name.rawValue)\(defaultValue)"
        }.joined(separator: "\n")
        return """
        \(access)init(\(parameters)) {
        \(assignments.indented)
        }
        """
    }

    func renderCodingKeys(properties: [Property]) -> String {
        let cases = properties
            .map { "case \($0.name.rawValue) = \($0.key.swiftStringLiteral)" }
            .joined(separator: "\n")
        return """
        \(access)enum CodingKeys: String, CodingKey {
        \(cases.indented)
        }
        """
    }

    func renderDecode(properties: [Property]) -> String {
        let statements = properties.map { property in
            let method = property.isOptional ? "decodeIfPresent" : "decode"
            let defaultValue = (property.isOptional && property.defaultValue != nil) ? " ?? \(property.defaultValue!)" : ""
            return "self.\(property.name.accessor) = try values.\(method)(\(property.type).self, forKey: \(codingKey(for: property)))\(defaultValue)"
        }.joined(separator: "\n")
        return """
        \(access)init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: \(keyedContainerType).self)
        \(statements.indented)
        }
        """
    }

    func renderEncode(properties: [Property]) -> String {
        let statements = properties.map { property in
            let method = property.isOptional ? "encodeIfPresent" : "encode"
            let getter = property.name.rawValue == "values" ? "self.values" : property.name.rawValue
            return "try values.\(method)(\(getter), forKey: \(codingKey(for: property)))"
        }.joined(separator: "\n")
        return """
        \(access)func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: \(keyedContainerType).self)
        \(statements.indented)
        }
        """
    }

    var keyedContainerType: String {
        switch plan.config.entities.codingStrategy {
        case .codingKeys:
            "CodingKeys"
        case .stringCodingKey:
            "StringCodingKey"
        }
    }

    func codingKey(for property: Property) -> String {
        switch plan.config.entities.codingStrategy {
        case .codingKeys:
            ".\(property.name.rawValue)"
        case .stringCodingKey:
            property.key.swiftStringLiteral
        }
    }

    func renderAnyOfDecode(properties: [Property]) -> String {
        let statements = properties.map { "self.\($0.name.accessor) = try? container.decode(\($0.type).self)" }.joined(separator: "\n")
        return """
        \(access)init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
        \(statements.indented)
        }
        """
    }

    func renderAnyOfEncode(properties: [Property]) -> String {
        let statements = properties.map { "if let value = \($0.name.rawValue) { try container.encode(value) }" }.joined(separator: "\n")
        return """
        \(access)func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
        \(statements.indented)
        }
        """
    }

    func renderOneOfDecode(properties: [Property]) -> String {
        var statements = ""
        for property in properties {
            statements += "if let value = try? container.decode(\(property.type).self) {\n    self = .\(property.name.rawValue)(value)\n} else "
        }
        let list = properties.map(\.type.name.rawValue).joined(separator: ", ")
        statements += """
        {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Data could not be decoded as any of the expected types (\(list))."
            )
        }
        """
        return """
        \(access)init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
        \(statements.indented)
        }
        """
    }

    /// Reads the discriminator field first so decoding can pick the mapped case directly.
    func renderOneOfDecodeWithDiscriminator(properties: [Property], discriminator: Discriminator) -> String {
        let propertyName = discriminator.propertyName == "Type" ? PropertyName("_Type") : PropertyName(discriminator.propertyName)
        let propertiesByType = Dictionary(grouping: properties, by: \.type)
        let cases = discriminator.mapping.sorted { $0.key < $1.key }.compactMap { key, type -> String? in
            guard let caseName = discriminator.cases[key] ?? propertiesByType[type]?.first?.name else { return nil }
            return "case \"\(key)\": self = try .\(caseName.rawValue)(container.decode(\(type).self))"
        }.joined(separator: "\n")
        let expected = discriminator.mapping.keys.sorted()
        return """
        \(access)init(from decoder: Decoder) throws {

            struct Discriminator: Decodable {
                let \(propertyName.rawValue): String
            }

            let container = try decoder.singleValueContainer()
            let discriminatorValue = try container.decode(Discriminator.self).\(propertyName.accessor)

            switch discriminatorValue {
        \(cases.indented)
            default:
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Discriminator value '\\(discriminatorValue)' does not match any expected values (\(expected
            .joined(separator: ", ")))."
                )
            }
        }
        """
    }

    func renderOneOfEncode(properties: [Property]) -> String {
        let cases = properties.map { "case let .\($0.name.rawValue)(value): try container.encode(value)" }.joined(separator: "\n")
        return """
        \(access)func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
        \(cases.indented)
            }
        }
        """
    }

    func renderAsQuery(properties: [Property]) -> String {
        state.usage.usesQueryEncoder = true
        let statements = properties.map { queryEncode($0) }.joined(separator: "\n")
        return """
        \(access)var asQuery: [(String, String?)] {
            let encoder = URLQueryEncoder()
        \(statements.indented)
            return encoder.items
        }
        """
    }

    func renderInlineQueryFunction(name: String, properties: [Property], isStatic: Bool) -> String {
        let args = properties.map { "_ \($0.name.rawValue): \($0.type)\($0.isOptional ? "?" : "")" }.joined(separator: ", ")
        let statements = properties.map { queryEncode($0) }.joined(separator: "\n")
        return """
        private \(isStatic ? "static " : "")func \(name)(\(args)) -> [(String, String?)] {
            let encoder = URLQueryEncoder()
        \(statements.indented)
            return encoder.items
        }
        """
    }

    func queryEncode(_ property: Property) -> String {
        var parameters = [property.name.rawValue, "forKey: \"\(property.key)\""]
        if !property.explode {
            parameters.append("explode: false")
        }
        switch property.style {
        case .pipeDelimited:
            parameters.append("delimiter: \"|\"")
        case .spaceDelimited:
            parameters.append("delimiter: \" \"")
        case .deepObject:
            parameters.append("isDeepObject: true")
        default:
            break
        }
        return "encoder.encode(\(parameters.joined(separator: ", ")))"
    }

    func keyValuePairs(_ properties: [Property]) -> String {
        let pairs = properties.map { property in
            let value = property.type.isString ? property.name.rawValue : "String(\(property.name.rawValue))"
            return "(\"\(property.key)\", \(value))"
        }
        return "[\(pairs.joined(separator: ", "))]"
    }

    func enumCase(name: String, value: String) -> String {
        if name.trimmingCharacters(in: .ticks) == value {
            return "case \(name)"
        }
        return "case \(name) = \(value.swiftStringLiteral)"
    }

    func resolveType(for declaration: EntityDecl) -> String {
        if declaration.kind == .oneOf {
            return "enum"
        }
        if declaration.isRenderedAsStruct {
            return "struct"
        }
        switch plan.config.entities.preferredType(of: declaration.name.rawValue) {
        case .struct:
            return "struct"
        case .class:
            return "class"
        case .finalClass:
            return "final class"
        }
    }
}
