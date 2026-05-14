import Foundation
import OpenAPIKit30

extension CodeGen {
    func pathFileJobs() throws -> [PathFileJob] {
        switch plan.config.paths.style {
        case .operations:
            try operationPathFileJobs()
        case .rest:
            try restPathFileJobs()
        }
    }

    func renderPathFiles(_ jobs: [PathFileJob]) throws -> [GeneratedFile] {
        try jobs.map { job in
            switch job {
            case let .operation(job):
                let body = renderOperation(job.declaration)
                let source = sourceFile(imports: pathImports(), body: body)
                return GeneratedFile(
                    relativePath: "Paths/\(template(plan.config.paths.filenameTemplate, job.filename))",
                    contents: source
                )
            case let .rest(job):
                let body = try renderRestPath(job.job, operations: job.operations)
                let source = sourceFile(imports: pathImports(), body: body)
                return GeneratedFile(
                    relativePath: "Paths/\(template(plan.config.paths.filenameTemplate, job.job.filename))",
                    contents: source
                )
            }
        }
    }

    func shouldGeneratePath(_ path: String) -> Bool {
        if !plan.config.paths.include.isEmpty {
            return plan.config.paths.include.contains(path)
        }
        if !plan.config.paths.exclude.isEmpty {
            return !plan.config.paths.exclude.contains(path)
        }
        return true
    }

    func pathImports() -> Set<String> {
        var imports = plan.config.paths.imports
        imports.remove("URLQueryEncoder")
        return imports
    }

    func makeOperation(
        path: OpenAPI.Path,
        item: OpenAPI.PathItem,
        method: String,
        operation: OpenAPI.Operation,
        operationID: String,
        baseName: TypeName,
        memberName: PropertyName,
        isStatic: Bool,
        usesStoredPath: Bool
    ) throws -> PathOp {
        let context = MakeContext()
        var parameters: [FuncParam] = []
        var call: [String] = []
        var nested: [SwiftDecl] = []

        if usesStoredPath {
            call.append("path: path")
        } else {
            var interpolatedPath = path.rawValue
            for parameter in try pathParameters(item: item, operation: operation) {
                if let range = interpolatedPath.range(of: "{\(parameter.key)}") {
                    interpolatedPath.replaceSubrange(range, with: "\\(\(parameter.name.rawValue))")
                }
                parameters.append(.init(
                    label: parameter.name.rawValue,
                    externalName: parameter.name.rawValue,
                    type: .builtin(parameter.type.rawValue),
                    defaultValue: nil
                ))
            }
            if interpolatedPath.contains("{") {
                throw GeneratorError("One or more path parameters for \(operationID) is missing")
            }
            call.append("path: \"\(interpolatedPath)\"")
        }
        call.append("method: \"\(method.uppercased())\"")

        let response = try responseType(operation: operation, nestedTypeName: baseName.appending("Response"), context: context)
        if let nestedResponse = response.nested {
            nested.append(nestedResponse)
        }

        let query = try operation.parameters.compactMap { try queryParameter($0, context: context) }.removingDuplicates(by: \.name)
        if query.isEmpty {
        } else if let limit = plan.config.paths.inlineQueryParameterLimit, query.count <= limit, query.allSatisfy({ $0.nested == nil }) {
            for item in query {
                parameters.append(.init(
                    label: item.name.rawValue,
                    externalName: item.name.rawValue,
                    type: item.type,
                    defaultValue: item.isOptional ? "nil" : nil,
                    isOptional: item.isOptional
                ))
            }
            if query.count < 3,
               query.allSatisfy({ ["String", "Int", "Double", "Bool"].contains($0.type.name.rawValue) && !$0.isOptional })
            {
                call.append("query: \(keyValuePairs(query))")
            } else {
                state.usage.usesQueryEncoder = true
                let functionName = "make\(baseName.appending("Query").rawValue)"
                call.append("query: \(functionName)(\(query.map(\.name.rawValue).joined(separator: ", ")))")
                nested.append(InlineFunctionDecl(
                    name: TypeName(functionName),
                    contents: renderInlineQueryFunction(name: functionName, properties: query, isStatic: isStatic)
                ))
            }
        } else {
            state.usage.usesQueryEncoder = true
            let type = baseName.appending("Parameters")
            let allOptional = query.allSatisfy(\.isOptional)
            parameters.append(.init(
                label: "parameters",
                externalName: "parameters",
                type: .userDefined(type),
                defaultValue: allOptional ? "nil" : nil,
                isOptional: allOptional
            ))
            call.append("query: parameters\(allOptional ? "?" : "").asQuery")
            let entity = EntityDecl(name: type, kind: .object, metadata: .empty, isForm: true)
            entity.properties = query
            entity.protocols = []
            entity.isRenderedAsStruct = true
            nested.append(entity)
        }

        if let requestBody = operation.requestBody, method != "get" {
            let body = try requestBodyType(requestBody, nestedTypeName: baseName.appending("Request"), context: context)
            if !body.type.isVoid {
                if plan.config.paths.inlineSimpleRequests,
                   let entity = body.nested as? EntityDecl,
                   entity.properties.count == 1,
                   !entity.isForm,
                   !parameters.contains(where: { $0.label == entity.properties[0].name.rawValue })
                {
                    let property = entity.properties[0]
                    parameters.append(.init(
                        label: property.name.rawValue,
                        externalName: property.name.rawValue,
                        type: property.type,
                        defaultValue: property.isOptional ? "nil" : nil,
                        isOptional: property.isOptional
                    ))
                    if property.nested == nil {
                        call.append("body: [\"\(property.key)\": \(property.name.rawValue)]")
                    } else {
                        call.append("body: \(entity.name.rawValue)(\(property.name.rawValue): \(property.name.rawValue))")
                        nested.append(entity)
                    }
                } else {
                    parameters.append(.init(
                        label: "body",
                        externalName: "_",
                        type: body.type,
                        defaultValue: body.isOptional ? "nil" : nil,
                        isOptional: body.isOptional
                    ))
                    call.append("body: body")
                    if let bodyNested = body.nested {
                        nested.append(bodyNested)
                    }
                }
            }
        }

        if !operationID.isEmpty {
            call.append("id: \"\(operationID)\"")
        }
        return PathOp(
            name: memberName,
            isStatic: isStatic,
            summary: operation.summary,
            description: operation.description,
            isDeprecated: operation.deprecated,
            responseType: response.type,
            parameters: parameters,
            requestExpression: "Request(\(call.joined(separator: ", ")))",
            nested: nested.removingDuplicates(by: \.name)
        )
    }

    func pathParameters(item: OpenAPI.PathItem, operation: OpenAPI.Operation) throws -> [PathParam] {
        try (item.parameters + operation.parameters)
            .compactMap { try $0.unwrapped(in: plan.document) }
            .filter(\.context.inPath)
            .map { parameter in
                let schema = try parameter.unwrapped(in: plan.document).schema.unwrapped(in: plan.document)
                let type = if case .integer = schema.value {
                    TypeName("Int")
                } else {
                    TypeName("String")
                }
                return PathParam(key: parameter.name, name: names.property(parameter.name), type: type)
            }
    }

    func queryParameter(
        _ input: Either<JSONReference<OpenAPI.Parameter>, OpenAPI.Parameter>,
        context: MakeContext
    ) throws -> Property? {
        let parameter = try input.unwrapped(in: plan.document)
        guard parameter.context.inQuery else { return nil }
        let schemaContext = try parameter.unwrapped(in: plan.document)
        let schema = try schemaContext.schema.unwrapped(in: plan.document)
        var context = context
        context.isFormEncoding = true
        let type = try queryType(parameterName: parameter.name, schema: schema, context: context)
        guard !type.type.isVoid else { return nil }
        let generatedParameterName = names.property(parameter.name).rawValue
        let renamedParameterName = plan.config.rename.parameters[generatedParameterName] ?? parameter.name
        var propertyName = names.property(renamedParameterName)
        if type.type.isBool, plan.config.useSwiftyPropertyNames {
            propertyName = propertyName.asBoolean(acronyms: plan.config.acronyms)
        }
        return Property(
            name: propertyName,
            type: type.type,
            isOptional: !parameter.required,
            key: parameter.name,
            explode: schemaContext.explode,
            style: schemaContext.style,
            metadata: .init(schema.coreContext),
            nested: type.nested
        )
    }

    func queryType(
        parameterName: String,
        schema: JSONSchema,
        context: MakeContext
    ) throws -> (type: SwiftType, nested: SwiftDecl?) {
        switch schema.value {
        case .boolean:
            return (.builtin("Bool"), nil)
        case let .number(info, _):
            return (numberType(for: info.format), nil)
        case let .integer(info, _):
            return (integerType(for: info.format), nil)
        case let .string(info, _):
            if info.allowedValues != nil {
                let name = names.type(parameterName)
                return try (.userDefined(name), makeStringEnum(name: name, info: info))
            }
            return (stringType(for: info.format), nil)
        case let .array(_, details):
            guard let item = details.items else { throw GeneratorError("Missing array item type") }
            let itemType = try queryType(parameterName: parameterName, schema: item, context: context)
            return (.array(itemType.type), itemType.nested)
        case let .reference(reference, _):
            return try (referenceType(reference, context: context), nil)
        case let .all(schemas, _) where schemas.count == 1:
            if case let .reference(reference, _) = schemas[0].value {
                return try (referenceType(reference, context: context), nil)
            }
            return try queryType(parameterName: parameterName, schema: schemas[0], context: context)
        case .object, .all, .one, .any:
            let name = names.type(parameterName)
            let declaration = try makeDeclaration(name: name, schema: schema, context: context)
            if let alias = declaration as? TypealiasDecl {
                return (alias.type, alias.nested)
            }
            return (.userDefined(name), declaration)
        case .fragment:
            return (.builtin("String"), nil)
        case .not:
            throw GeneratorError("Unsupported query parameter type \(parameterName)")
        }
    }

    func responseType(operation: OpenAPI.Operation, nestedTypeName: TypeName, context: MakeContext) throws -> BodyUse {
        guard let response = operation.firstSuccessfulResponse else {
            return BodyUse(type: .builtin("Void"), nested: nil, isOptional: false)
        }
        let resolved: OpenAPI.Response
        switch response {
        case let .a(reference):
            guard let name = reference.name else { throw GeneratorError("Response reference name is missing") }
            if let override = plan.config.paths.responseTypeOverrides[name] {
                return BodyUse(type: .userDefined(TypeName(override)), nested: nil, isOptional: false)
            }
            guard let key = OpenAPI.ComponentKey(rawValue: name), let value = plan.document.components.responses[key] else {
                throw GeneratorError("Failed to find response \(name)")
            }
            resolved = value
        case let .b(value):
            resolved = value
        }
        return try bodyType(content: resolved.content, nestedTypeName: nestedTypeName, context: context)
    }

    func requestBodyType(
        _ requestBody: Either<JSONReference<OpenAPI.Request>, OpenAPI.Request>,
        nestedTypeName: TypeName,
        context: MakeContext
    ) throws -> BodyUse {
        let request = try requestBody.unwrapped(in: plan.document)
        var body = try bodyType(content: request.content, nestedTypeName: nestedTypeName, context: context)
        body.isOptional = !(requestBody.requestValue?.required ?? true)
        return body
    }

    func bodyType(content: OpenAPI.Content.Map, nestedTypeName: TypeName, context: MakeContext) throws -> BodyUse {
        if content.values.isEmpty {
            return BodyUse(type: .builtin("Void"), nested: nil, isOptional: false)
        }

        let contentByTypeAndSubtype = contentByTypeAndSubtype(content)
        for key in content.keys {
            if let override = plan.config.paths.bodyTypeOverrides[key.rawValue] {
                return BodyUse(type: .userDefined(TypeName(override)), nested: nil, isOptional: false)
            }
        }

        if let content = firstContent(
            in: contentByTypeAndSubtype,
            matching: [
                .json,
                .jsonapi,
                .other("application/scim+json"),
                .other("application/json"),
                .other("text/json"),
                .other("application/*+json")
            ]
        ) {
            switch content.schema {
            case let .a(reference):
                let type = try referenceType(reference, context: context)
                return BodyUse(type: type, nested: nil, isOptional: false)
            case let .b(schema):
                switch schema.value {
                case let .string(info, _):
                    return BodyUse(type: stringType(for: info.format), nested: nil, isOptional: false)
                case .integer, .boolean:
                    return BodyUse(type: .builtin("Data"), nested: nil, isOptional: false)
                default:
                    var context = context
                    let value = try typeIdentifier(for: schema, fallback: nestedTypeName.rawValue, context: &context)
                    return BodyUse(type: value.type, nested: value.nested, isOptional: false)
                }
            default:
                return BodyUse(type: .builtin("String"), nested: nil, isOptional: false)
            }
        }
        if firstContent(
            in: contentByTypeAndSubtype,
            matching: [
                .css,
                .csv,
                .html,
                .javascript,
                .txt,
                .xml,
                .yaml,
                .anyText,
                .other("text/xml"),
                .other("plain/text"),
                .other("text/plain")
            ]
        ) != nil {
            return BodyUse(type: .builtin("String"), nested: nil, isOptional: false)
        }
        return BodyUse(type: .builtin("Data"), nested: nil, isOptional: false)
    }

    func contentByTypeAndSubtype(_ map: OpenAPI.Content.Map) -> [String: OpenAPI.Content] {
        var output: [String: OpenAPI.Content] = [:]
        for (key, value) in map where output[key.typeAndSubtype] == nil {
            output[key.typeAndSubtype] = value
        }
        return output
    }

    func firstContent(in map: [String: OpenAPI.Content], matching keys: [OpenAPI.ContentType]) -> OpenAPI.Content? {
        for key in keys {
            if let content = map[key.typeAndSubtype] {
                return content
            }
        }
        return nil
    }
}
