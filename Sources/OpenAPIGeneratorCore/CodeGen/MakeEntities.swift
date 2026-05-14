import Foundation
import OpenAPIKit30

extension CodeGen {
    func entityFileJobs() throws -> [EntityFileJob] {
        let jobs = plan.document.components.schemas.compactMap { key, schema -> (TypeName, JSONSchema)? in
            guard let name = typeName(for: key), shouldGenerateEntity(name.rawValue) else { return nil }
            guard !shouldRemoveDeprecated(schema.coreContext?.deprecated ?? false) else { return nil }
            return (name, schema)
        }
        state.topLevelTypes = Set(jobs.map(\.0))

        let declarations = try jobs.map { name, schema in
            try makeDeclaration(name: name, schema: schema, context: .init())
        }

        for declaration in declarations {
            if let entity = declaration as? EntityDecl {
                state.madeSchemas[entity.name] = entity
            }
        }

        return zip(jobs, declarations).map { job, declaration in
            EntityFileJob(name: job.0, declaration: declaration)
        }
    }

    func renderEntityFiles(_ jobs: [EntityFileJob]) throws -> [GeneratedFile] {
        try jobs.compactMap { job in
            let declaration = job.declaration
            if declaration is TypealiasDecl {
                return nil
            }
            let source = try sourceFile(
                imports: plan.config.entities.imports,
                body: render(declaration)
            )
            return GeneratedFile(
                relativePath: "Entities/\(template(plan.config.entities.filenameTemplate, job.name.rawValue))",
                contents: source
            )
        }
    }

    func typeName(for key: OpenAPI.ComponentKey) -> TypeName? {
        if let cached = state.componentTypeNames[key.rawValue] {
            return cached
        }
        var rawName = key.rawValue
        if let renamed = plan.config.rename.entities[names.type(rawName).rawValue] ?? plan.config.rename.entities[rawName] {
            rawName = renamed
        }
        let name = names.type(template(plan.config.entities.nameTemplate, rawName))
        state.componentTypeNames[key.rawValue] = name
        return name
    }

    func shouldGenerateEntity(_ name: String) -> Bool {
        if !plan.config.entities.include.isEmpty {
            return plan.config.entities.include.contains(name)
        }
        return !state.excludedEntities.contains(name)
    }

    func makeDeclaration(name: TypeName, schema: JSONSchema, context: MakeContext) throws -> SwiftDecl {
        switch schema.value {
        case .boolean:
            return TypealiasDecl(name: name, type: .builtin("Bool"))
        case let .number(info, _):
            return TypealiasDecl(name: name, type: numberType(for: info.format))
        case let .integer(info, _):
            return TypealiasDecl(name: name, type: integerType(for: info.format))
        case let .string(info, _):
            if plan.config.entities.stringEnums, info.allowedValues != nil {
                return try makeStringEnum(name: name, info: info)
            }
            return TypealiasDecl(name: name, type: stringType(for: info.format))
        case let .object(info, details):
            return try makeObject(name: name, info: info, details: details, context: context)
        case let .array(_, details):
            guard let item = details.items else { throw GeneratorError("Missing array item type") }
            let itemName = names.type(singularized(name.rawValue))
            let itemDeclaration = try makeDeclaration(name: itemName, schema: item, context: context)
            if let alias = itemDeclaration as? TypealiasDecl {
                return TypealiasDecl(name: name, type: .array(alias.type), nested: alias.nested)
            }
            return TypealiasDecl(name: name, type: .array(.userDefined(itemName)), nested: itemDeclaration)
        case let .all(schemas, _) where schemas.count == 1:
            return try makeDeclaration(name: name, schema: schemas[0], context: context)
        case let .one(schemas, _) where schemas.count == 1:
            return try makeDeclaration(name: name, schema: schemas[0], context: context)
        case let .any(schemas, _) where schemas.count == 1:
            return try makeDeclaration(name: name, schema: schemas[0], context: context)
        case let .all(schemas, info):
            return try makeAllOf(name: name, schemas: schemas, info: info, context: context)
        case let .one(schemas, info):
            return try makeOneOf(name: name, schemas: schemas, info: info, context: context)
        case let .any(schemas, info):
            return try makeAnyOf(name: name, schemas: schemas, info: info, context: context)
        case let .reference(reference, _):
            return try TypealiasDecl(name: name, type: referenceType(reference, context: context))
        case .fragment:
            state.usage.usesAnyJSON = true
            return TypealiasDecl(name: name, type: .userDefined(TypeName("AnyJSON")))
        case .not:
            throw GeneratorError("Unsupported schema 'not' for \(name.rawValue)")
        }
    }

    func makeObject(
        name: TypeName,
        info: JSONSchemaContext,
        details: JSONSchema.ObjectContext,
        context: MakeContext
    ) throws -> SwiftDecl {
        if let dictionary = try dictionaryType(key: name.rawValue, info: info, details: details, context: context) {
            return TypealiasDecl(name: name, type: dictionary.type, nested: dictionary.nested)
        }

        var context = context
        let entity = EntityDecl(name: name, kind: .object, metadata: .init(info), isForm: context.isFormEncoding)
        context.parents.append(entity)

        let properties: [Property] = try details.properties.keys.compactMap { key in
            guard !isExcludedProperty(key: key, from: name) else { return nil }
            guard let schema = details.properties[key] else { return nil }
            guard !shouldRemoveDeprecated(schema.coreContext?.deprecated ?? false) else { return nil }
            let property = try makeProperty(
                key: key,
                schema: schema,
                isRequired: details.requiredProperties.contains(key),
                context: context,
                isInlined: true
            )
            return isExcludedProperty(property, from: name) ? nil : property
        }.filter { !$0.type.isVoid }.removingDuplicates(by: \.name)
        entity.properties = sortedProperties(properties)
        entity.protocols = protocols(for: entity, context: context)
        return entity
    }

    func makeAllOf(name: TypeName, schemas: [JSONSchema], info: JSONSchemaContext, context: MakeContext) throws -> SwiftDecl {
        var context = context
        let entity = EntityDecl(name: name, kind: .allOf, metadata: .init(info), isForm: context.isFormEncoding)
        context.parents.append(entity)

        entity.properties = try schemas.flatMap { schema -> [Property] in
            switch schema.value {
            case let .object(_, details):
                return try details.properties.keys.compactMap { key in
                    guard !isExcludedProperty(key: key, from: name) else { return nil }
                    guard !shouldRemoveDeprecated(details.properties[key]?.coreContext?.deprecated ?? false) else { return nil }
                    let property = try makeProperty(
                        key: key,
                        schema: details.properties[key]!,
                        isRequired: details.requiredProperties.contains(key),
                        context: context,
                        isInlined: true
                    )
                    return isExcludedProperty(property, from: name) ? nil : property
                }
            case let .reference(reference, _):
                if plan.config.entities.inlineReferencedSchemas,
                   let referenced = referencedSchema(for: reference),
                   case let .object(_, details) = referenced.value
                {
                    return try details.properties.keys.compactMap { key in
                        guard !isExcludedProperty(key: key, from: name) else { return nil }
                        guard !shouldRemoveDeprecated(details.properties[key]?.coreContext?.deprecated ?? false) else { return nil }
                        let property = try makeProperty(
                            key: key,
                            schema: details.properties[key]!,
                            isRequired: details.requiredProperties.contains(key),
                            context: context,
                            isInlined: true
                        )
                        return isExcludedProperty(property, from: name) ? nil : property
                    }
                }
                let type = try referenceType(reference, context: context)
                return [Property(
                    name: names.property(type.name.rawValue),
                    type: type,
                    isOptional: false,
                    key: type.name.rawValue,
                    metadata: .init(schema.coreContext),
                    isInlined: false
                )]
            default:
                let typeName = makeTypeName(for: schema, fallback: "Object", context: context)
                return try [makeProperty(key: typeName.rawValue, schema: schema, isRequired: true, context: context, isInlined: true)]
            }
        }.removingDuplicates(by: \.name)
        entity.properties = sortedProperties(entity.properties)
        entity.protocols = protocols(for: entity, context: context)
        return entity
    }

    func excludedProperties(for name: TypeName) -> Set<String> {
        state.excludedPropertiesByEntity[name.rawValue] ?? []
    }

    func isExcludedProperty(key: String, from name: TypeName) -> Bool {
        excludedProperties(for: name).contains(key)
    }

    func isExcludedProperty(_ property: Property, from name: TypeName) -> Bool {
        let propertyName = property.name.rawValue.trimmingCharacters(in: .ticks)
        return excludedProperties(for: name).contains(propertyName)
    }

    func sortedProperties(_ properties: [Property]) -> [Property] {
        guard plan.config.entities.sortProperties else { return properties }
        return properties.sorted { $0.name.rawValue < $1.name.rawValue }
    }

    func makeAnyOf(name: TypeName, schemas: [JSONSchema], info: JSONSchemaContext, context: MakeContext) throws -> SwiftDecl {
        var context = context
        let entity = EntityDecl(name: name, kind: .anyOf, metadata: .init(info), isForm: context.isFormEncoding)
        context.parents.append(entity)
        entity.properties = try makeVariantProperties(schemas: schemas, context: context).filter { !$0.type.isVoid }
        entity.protocols = protocols(for: entity, context: context)
        return entity
    }

    func makeOneOf(name: TypeName, schemas: [JSONSchema], info: JSONSchemaContext, context: MakeContext) throws -> SwiftDecl {
        var context = context
        let entity = EntityDecl(name: name, kind: .oneOf, metadata: .init(info), isForm: context.isFormEncoding)
        context.parents.append(entity)
        entity.properties = try makeVariantProperties(schemas: schemas, context: context).removingDuplicates(by: \.type)
        entity.protocols = protocols(for: entity, context: context)
        entity.discriminator = try discriminator(info: info, context: context)
        return entity
    }

    func makeVariantProperties(schemas: [JSONSchema], context: MakeContext) throws -> [Property] {
        let typeNames = schemas.map { makeTypeName(for: $0, fallback: "Object", context: context).rawValue }.disambiguateDuplicateNames()
        return try zip(typeNames, schemas).map { key, schema in
            try makeProperty(key: key, schema: schema, isRequired: false, context: context)
        }
    }

    func makeStringEnum(name: TypeName, info: JSONSchemaContext) throws -> SwiftDecl {
        let values = (info.allowedValues ?? []).compactMap { $0.value as? String }
        guard !values.isEmpty else { throw GeneratorError("Enum \(name.rawValue) has no values") }
        var deduplicator = NameDeduplicator()
        let cases = values.map { value -> EnumCase in
            let renamed = plan.config.rename.enumCases["\(name.rawValue).\(value)"] ?? plan.config.rename.enumCases[value]
            let rawCaseName = renamed ?? sanitizeEnumCaseName(value).trimmingCharacters(in: .whitespaces)
            let caseName = rawCaseName.isEmpty ? "empty" : rawCaseName
            return EnumCase(name: deduplicator.add(name: names.property(caseName).rawValue), rawValue: value)
        }
        return StringEnumDecl(name: name, cases: cases, metadata: .init(info))
    }

    func makeProperty(
        key: String,
        schema: JSONSchema,
        isRequired: Bool,
        context: MakeContext,
        isInlined: Bool? = nil
    ) throws -> Property {
        let renamedKey = renamedProperty(key: key, context: context)
        let overridePropertyName = makePropertyName(for: renamedKey, schema: schema)
        let overriddenType = propertyTypeOverride(key: key, propertyName: overridePropertyName, context: context)

        let type: (type: SwiftType, nested: SwiftDecl?)
        let propertyName: PropertyName
        if let overriddenType {
            type = (.builtin(TypeName(overriddenType)), nil)
            propertyName = overridePropertyName
        } else {
            var typeContext = context
            type = try typeIdentifier(for: schema, fallback: key, context: &typeContext)
            propertyName = makePropertyName(for: renamedKey, type: type.type)
        }

        let nullable = schema.coreContext?.nullable ?? false
        let resolvedType = type.type
        let isOptional = !isRequired || nullable

        var defaultValue: String?
        if plan.config.entities.defaultValues, resolvedType.isBool {
            defaultValue = (schema.coreContext?.defaultValue?.value as? Bool).map { $0 ? "true" : "false" }
        }

        let qualified = "\(context.parents.first?.name.rawValue ?? "").\(propertyName.rawValue.trimmingCharacters(in: .ticks))"
        let isIndirect = plan.config.entities.indirectProperties.contains(qualified)
        if isIndirect {
            state.usage.usesIndirect = true
        }

        return Property(
            name: propertyName,
            type: resolvedType,
            isOptional: isOptional,
            key: key,
            defaultValue: defaultValue,
            metadata: .init(schema.coreContext),
            nested: type.nested,
            isInlined: isInlined,
            isIndirect: isIndirect
        )
    }

    func makePropertyName(for key: String, schema: JSONSchema) -> PropertyName {
        let propertyName = names.property(key)
        guard isBooleanSchema(schema), plan.config.useSwiftyPropertyNames else { return propertyName }
        return propertyName.asBoolean(acronyms: plan.config.acronyms)
    }

    func makePropertyName(for key: String, type: SwiftType) -> PropertyName {
        let propertyName = names.property(key)
        guard type.isBool, plan.config.useSwiftyPropertyNames else { return propertyName }
        return propertyName.asBoolean(acronyms: plan.config.acronyms)
    }

    func propertyTypeOverride(key: String, propertyName: PropertyName, context: MakeContext) -> String? {
        guard let entityName = context.parents.first?.name.rawValue else { return nil }
        let generatedName = propertyName.rawValue.trimmingCharacters(in: .ticks)
        let overrides = plan.config.entities.propertyTypeOverrides
        return overrides["\(entityName).\(generatedName)"] ?? overrides["\(entityName).\(key)"]
    }

    func isBooleanSchema(_ schema: JSONSchema) -> Bool {
        if case .boolean = schema.value {
            return true
        }
        return false
    }

    func typeIdentifier(
        for schema: JSONSchema,
        fallback: String,
        context: inout MakeContext
    ) throws -> (type: SwiftType, nested: SwiftDecl?) {
        let name = usesInlineTypeName(for: schema) ? inlineTypeName(fallback: fallback) : names.type(fallback)
        let declaration = try makeDeclaration(name: name, schema: schema, context: context)
        if let alias = declaration as? TypealiasDecl {
            return (alias.type, alias.nested)
        }
        return (.userDefined(declaration.name), declaration)
    }

    func referenceType(_ reference: JSONReference<JSONSchema>, context: MakeContext) throws -> SwiftType {
        guard let referenceName = reference.name else { throw GeneratorError("Reference name is missing") }
        let canInlineTypealias = plan.config.inlineTypealiases && !context.parents.contains(where: { $0.name.rawValue == referenceName })
        let cacheKey = ReferenceTypeCacheKey(
            referenceName: referenceName,
            namespace: context.namespace,
            canInlineTypealias: canInlineTypealias
        )
        if let cached = state.referenceTypes[cacheKey] {
            return cached
        }
        if let key = OpenAPI.ComponentKey(rawValue: referenceName), plan.document.components.schemas[key] == nil {
            state.usage.usesAnyJSON = true
            let type = SwiftType.userDefined(TypeName("AnyJSON"))
            state.referenceTypes[cacheKey] = type
            return type
        }
        if canInlineTypealias,
           let key = OpenAPI.ComponentKey(rawValue: referenceName),
           let schema = plan.document.components.schemas[key]
        {
            if let inlineType = try inlineTypealiasType(name: names.type(referenceName), schema: schema, context: context) {
                let type = inlineType.namespace(context.namespace)
                state.referenceTypes[cacheKey] = type
                return type
            }
        }
        let renamed = plan.config.rename.entities[referenceName] ?? referenceName
        let templated = template(plan.config.entities.nameTemplate, renamed)
        let type = SwiftType.userDefined(names.type(templated).namespace(context.namespace))
        state.referenceTypes[cacheKey] = type
        return type
    }

    func inlineTypealiasType(name: TypeName, schema: JSONSchema, context: MakeContext) throws -> SwiftType? {
        switch schema.value {
        case .boolean:
            return .builtin("Bool")
        case let .number(info, _):
            return numberType(for: info.format)
        case let .integer(info, _):
            return integerType(for: info.format)
        case let .string(info, _):
            if plan.config.entities.stringEnums, info.allowedValues != nil {
                return nil
            }
            return stringType(for: info.format)
        case let .array(_, details):
            guard let item = details.items else { throw GeneratorError("Missing array item type") }
            let itemName = names.type(singularized(name.rawValue))
            if let itemType = try inlineTypealiasType(name: itemName, schema: item, context: context) {
                return .array(itemType)
            }
            return .array(.userDefined(itemName))
        case let .all(schemas, _) where schemas.count == 1:
            return try inlineTypealiasType(name: name, schema: schemas[0], context: context)
        case let .one(schemas, _) where schemas.count == 1:
            return try inlineTypealiasType(name: name, schema: schemas[0], context: context)
        case let .any(schemas, _) where schemas.count == 1:
            return try inlineTypealiasType(name: name, schema: schemas[0], context: context)
        case .all, .one, .any:
            return nil
        case let .reference(reference, _):
            return try referenceType(reference, context: context)
        case .fragment:
            state.usage.usesAnyJSON = true
            return .userDefined(TypeName("AnyJSON"))
        case let .object(_, details):
            return try inlineDictionaryType(name: name, details: details, context: context)
        case .not:
            throw GeneratorError("Unsupported schema 'not' for \(name.rawValue)")
        }
    }

    func inlineDictionaryType(
        name: TypeName,
        details: JSONSchema.ObjectContext,
        context: MakeContext
    ) throws -> SwiftType? {
        let additionalProperties = details.additionalProperties ?? .a(true)
        switch additionalProperties {
        case let .a(allowed):
            if !allowed, details.properties.isEmpty {
                return .builtin("Void")
            }
            guard details.properties.isEmpty else { return nil }
            state.usage.usesAnyJSON = true
            return .dictionary(value: .userDefined(TypeName("AnyJSON")))
        case let .b(schema):
            let nestedName = names.type(singularized(name.rawValue))
            if let valueType = try inlineTypealiasType(name: nestedName, schema: schema, context: context) {
                return .dictionary(value: valueType)
            }
            return .dictionary(value: .userDefined(nestedName))
        }
    }

    func referencedSchema(for reference: JSONReference<JSONSchema>) -> JSONSchema? {
        guard let name = reference.name, let key = OpenAPI.ComponentKey(rawValue: name) else { return nil }
        return plan.document.components.schemas[key]
    }

    func dictionaryType(
        key: String,
        info _: JSONSchemaContext,
        details: JSONSchema.ObjectContext,
        context: MakeContext
    ) throws -> (type: SwiftType, nested: SwiftDecl?)? {
        let additionalProperties = details.additionalProperties ?? .a(true)
        switch additionalProperties {
        case let .a(allowed):
            if !allowed, details.properties.isEmpty {
                return (.builtin("Void"), nil)
            }
            if !details.properties.isEmpty {
                return nil
            }
            state.usage.usesAnyJSON = true
            return (.dictionary(value: .userDefined(TypeName("AnyJSON"))), nil)
        case let .b(schema):
            let nestedName = names.type(singularized(key))
            let declaration = try makeDeclaration(name: nestedName, schema: schema, context: context)
            if let alias = declaration as? TypealiasDecl {
                return (.dictionary(value: alias.type), alias.nested)
            }
            return (.dictionary(value: .userDefined(nestedName)), declaration)
        }
    }

    func discriminator(info: JSONSchemaContext, context: MakeContext) throws -> Discriminator? {
        try info.discriminator.flatMap { discriminator in
            var mappings: [String: SwiftType] = [:]
            mappings.reserveCapacity(discriminator.mapping?.count ?? 0)
            for (key, value) in discriminator.mapping ?? [:] {
                mappings[key] = try referenceType(discriminatorReference(value), context: context)
            }
            return Discriminator(
                propertyName: discriminator.propertyName,
                mapping: mappings
            )
        }
    }

    func discriminatorReference(_ value: String) throws -> JSONReference<JSONSchema> {
        if value.hasPrefix("#") {
            return .internal(.path(.init(rawValue: value)))
        }
        if let url = URL(string: value) {
            return .external(url)
        }
        throw GeneratorError("Expected mapping value '\(value)' to be a valid reference")
    }

    func protocols(for entity: EntityDecl, context _: MakeContext) -> [String] {
        var protocols = plan.config.entities.conformances
        if plan.config.entities.automaticIdentifiable,
           entity.properties.contains(where: { $0.name.rawValue == "id" && $0.type.isBuiltin })
        {
            protocols.insert("Identifiable")
        }
        return orderedProtocols(protocols)
    }

    func renamedProperty(key: String, context: MakeContext) -> String {
        let names = context.parents.map(\.name.rawValue) + [key]
        for index in names.indices {
            let candidate = names[index...].joined(separator: ".")
            if let renamed = plan.config.rename.properties[candidate] {
                return renamed
            }
        }
        return key
    }
}
