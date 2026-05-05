import OpenAPIKit30

extension CodeGen {
    func stringType(for format: JSONTypeFormat.StringFormat) -> SwiftType {
        switch format {
        case .byte:
            .builtin(plan.config.dataTypes.string["byte"] ?? "Data")
        case .binary:
            .builtin(plan.config.dataTypes.string["binary"] ?? "Data")
        case .date:
            .builtin(plan.config.dataTypes.string["date"] ?? "String")
        case .dateTime:
            .builtin(plan.config.dataTypes.string["date-time"] ?? "Date")
        case .other("uri"):
            .builtin(plan.config.dataTypes.string["uri"] ?? "URL")
        case .other("uuid"):
            .builtin(plan.config.dataTypes.string["uuid"] ?? "UUID")
        case let .other(format):
            .builtin(plan.config.dataTypes.string[format] ?? "String")
        case .generic, .password:
            .builtin("String")
        }
    }

    func numberType(for format: JSONTypeFormat.NumberFormat) -> SwiftType {
        switch format {
        case .double:
            .builtin(plan.config.dataTypes.number["double"] ?? "Double")
        case .float:
            .builtin(plan.config.dataTypes.number["float"] ?? "Float")
        case let .other(format):
            .builtin(plan.config.dataTypes.number[format] ?? "Double")
        case .generic:
            .builtin("Double")
        }
    }

    func integerType(for format: JSONTypeFormat.IntegerFormat) -> SwiftType {
        switch format {
        case .int32:
            .builtin(plan.config.dataTypes.integer["int32"] ?? "Int32")
        case .int64:
            .builtin(plan.config.dataTypes.integer["int64"] ?? "Int64")
        case let .other(format):
            .builtin(plan.config.dataTypes.integer[format] ?? "Int")
        case .generic:
            .builtin("Int")
        }
    }

    func makeTypeName(for schema: JSONSchema, fallback: String, context: MakeContext) -> TypeName {
        switch schema.value {
        case let .reference(reference, _):
            return names.type(reference.name ?? fallback)
        case let .array(_, details):
            if let item = details.items {
                let name = makeTypeName(for: item, fallback: fallback, context: context).rawValue
                return TypeName(plan.config.pluralizeProperties ? pluralized(names.property(name).rawValue) : names.property(name).rawValue)
            }
            return names.type(fallback)
        default:
            return names.type(fallback)
        }
    }
}
