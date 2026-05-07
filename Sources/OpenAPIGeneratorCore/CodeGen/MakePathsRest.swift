import Foundation
import OpenAPIKit30

extension CodeGen {
    struct RestPathJob {
        let types: [TypeName]
        let accessorName: PropertyName
        let component: String
        let path: OpenAPI.Path
        let components: [String]
        let isSubpath: Bool
        let item: OpenAPI.PathItem

        var type: TypeName {
            types.last ?? TypeName("Root")
        }

        var isTopLevel: Bool {
            components.count == 1
        }

        var filename: String {
            "Paths" + types.map(\.rawValue).joined()
        }
    }

    func restPathFiles() throws -> [GeneratedFile] {
        try makeRestPathJobs().map { job in
            let body = try renderRestPath(job)
            let source = sourceFile(imports: pathImports(), body: body)
            return GeneratedFile(
                relativePath: "Paths/\(template(plan.config.paths.filenameTemplate, job.filename))",
                contents: source
            )
        }
    }

    func makeRestPathJobs() throws -> [RestPathJob] {
        guard !plan.document.paths.isEmpty else { return [] }

        let commonIndices = findCommonPathComponentCount()
        var jobs: [RestPathJob] = []
        var encountered = Set<String>()
        var generatedNames: [String: Int] = [:]

        for (path, item) in plan.document.paths {
            guard shouldGeneratePath(path.rawValue) else { continue }
            let resolved = try item.unwrapped(in: plan.document)
            let components = pathComponents(path)
            for index in components.indices where index >= commonIndices {
                let subcomponents = Array(components[...index])
                let subpathRawValue = rawPath(from: subcomponents)
                let isSubpath = index < components.endIndex - 1
                if isSubpath, documentContainsPath(subpathRawValue), shouldGeneratePath(subpathRawValue) {
                    continue
                }
                guard encountered.insert(subpathRawValue).inserted else { continue }

                var types = subcomponents.map(restPathTypeName)
                let typesKey = types.map(\.rawValue).joined(separator: ".")
                var accessorName = restPathAccessorName(for: components[index])
                if let count = generatedNames[typesKey] {
                    if let last = types.popLast() {
                        types.append(last.appending("\(count + 1)"))
                    }
                    accessorName = PropertyName(accessorName.rawValue + "\(count + 1)")
                    generatedNames[typesKey] = count + 1
                } else {
                    generatedNames[typesKey] = 1
                }

                jobs.append(RestPathJob(
                    types: types,
                    accessorName: accessorName,
                    component: components[index],
                    path: OpenAPI.Path(rawValue: subpathRawValue),
                    components: Array(components[commonIndices ... index]),
                    isSubpath: isSubpath,
                    item: resolved
                ))
            }
        }

        return jobs
    }

    func findCommonPathComponentCount() -> Int {
        guard plan.config.paths.removeRedundantPaths else { return 0 }
        let paths = plan.document.paths.map(\.key)
        guard let first = paths.first else { return 0 }
        let firstComponents = pathComponents(first)
        var commonIndices = 0

        for index in firstComponents.indices {
            let component = firstComponents[index]
            for path in paths {
                let components = pathComponents(path)
                guard components.indices.contains(index), components[index] == component else {
                    return commonIndices
                }
                if components.indices.contains(index + 1), components[index + 1].contains("{") {
                    return commonIndices
                }
                if documentContainsPath(rawPath(from: Array(components[...index]))),
                   let item = plan.document.paths[OpenAPI.Path(rawValue: rawPath(from: Array(components[...index])))],
                   let resolved = try? item.unwrapped(in: plan.document),
                   !resolved.allOperations.isEmpty
                {
                    return commonIndices
                }
            }
            commonIndices += 1
        }
        return commonIndices
    }

    func renderRestPath(_ job: RestPathJob) throws -> String {
        let parentTypes = Array(job.types.suffix(job.components.count)).dropLast()
        let extensionOf = ([plan.config.paths.namespace] + parentTypes.map(\.rawValue)).joined(separator: ".")
        let accessor = try renderRestPathAccessor(job)
        let operations: [PathOp] = job.isSubpath ? [] : try job.item.allOperations.compactMap { method, operation in
            guard !shouldRemoveDeprecated(operation.deprecated) else { return nil }
            let operationID = operation.operationId ?? ""
            return try makeOperation(
                path: job.path,
                item: job.item,
                method: method,
                operation: operation,
                operationID: operationID,
                baseName: TypeName(method.capitalizingFirstLetter()),
                memberName: names.property(method),
                isStatic: false,
                usesStoredPath: true
            )
        }
        let entity = renderRestPathEntity(job, operations: operations)
        return renderPathExtension(of: extensionOf, contents: [accessor, entity].joined(separator: "\n\n"))
    }

    func renderRestPathAccessor(_ job: RestPathJob) throws -> String {
        guard let parameterName = pathParameterName(from: job.component) else {
            let expression = restPathExpression(for: job)
            let ownership = job.isTopLevel ? "static " : ""
            return """
            \(access)\(ownership)var \(job.accessorName.rawValue): \(job.type.rawValue) {
            \("\(job.type.rawValue)(path: \(expression))".indented)
            }
            """
        }

        let parameter = try pathParameter(item: job.item, name: parameterName)
        let expression = restPathExpression(for: job, parameter: parameter)
        let ownership = job.isTopLevel ? "static " : ""
        return """
        \(access)\(ownership)func \(job.accessorName.rawValue)(_ \(parameter.name.rawValue): \(parameter.type.rawValue)) -> \(job.type
            .rawValue) {
        \("\(job.type.rawValue)(path: \(expression))".indented)
        }
        """
    }

    func renderRestPathEntity(_ job: RestPathJob, operations: [PathOp]) -> String {
        let operationMembers = operations.map(renderPathMember).joined(separator: "\n\n")
        let contents = [
            """
            /// Path: `\(job.path.rawValue)`
            \(access)let path: String
            """,
            operationMembers,
        ].filter { !$0.isEmpty }.joined(separator: "\n\n")

        return """
        \(access)struct \(job.type.rawValue) {
        \(contents.indented)
        }
        """
    }

    func restPathExpression(for job: RestPathJob) -> String {
        if job.isTopLevel {
            return job.path.rawValue.swiftStringLiteral
        }
        let suffix = job.component.replacingOccurrences(of: "{", with: "\\(").replacingOccurrences(of: "}", with: ")")
        return "\"\\(path)/\(suffix)\""
    }

    func restPathExpression(for job: RestPathJob, parameter: PathParam) -> String {
        if job.isTopLevel {
            let path = job.path.rawValue.replacingOccurrences(
                of: "{\(parameter.key)}",
                with: "\\(\(parameter.name.rawValue))"
            )
            return "\"\(path)\""
        }
        let suffix = job.component.replacingOccurrences(
            of: "{\(parameter.key)}",
            with: "\\(\(parameter.name.rawValue))"
        )
        return "\"\\(path)/\(suffix)\""
    }

    func restPathTypeName(for component: String) -> TypeName {
        if component.isEmpty {
            return TypeName("Root")
        }
        if let parameter = pathParameterName(from: component) {
            if parameter.count == component.count - 2 {
                return names.type("with \(parameter)")
            }
            return names.type("with \(component.replacingOccurrences(of: "{\(parameter)}", with: parameter))")
        }
        return names.type(component)
    }

    func restPathAccessorName(for component: String) -> PropertyName {
        if component.isEmpty {
            return PropertyName("root")
        }
        if let parameter = pathParameterName(from: component) {
            return names.property(parameter)
        }
        return names.property(component)
    }

    func pathParameter(item: OpenAPI.PathItem, name: String) throws -> PathParam {
        let parameters = item.parameters.isEmpty ? (item.allOperations.first?.1.parameters ?? []) : item.parameters
        let parameter = try parameters
            .compactMap { try $0.unwrapped(in: plan.document) }
            .first { $0.context.inPath && $0.name == name }
        let type: TypeName
        if let parameter {
            let schema = try parameter.unwrapped(in: plan.document).schema.unwrapped(in: plan.document)
            type = if case .integer = schema.value {
                TypeName("Int")
            } else {
                TypeName("String")
            }
        } else {
            type = TypeName("String")
        }
        return PathParam(key: name, name: names.property(name), type: type)
    }

    func pathParameterName(from component: String) -> String? {
        guard let from = component.firstIndex(of: "{"),
              let to = component.firstIndex(of: "}"),
              from < to
        else {
            return nil
        }
        return String(component[component.index(after: from) ..< to])
    }

    func pathComponents(_ path: OpenAPI.Path) -> [String] {
        let rawValue = path.rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if rawValue.isEmpty {
            return [""]
        }
        return rawValue.split(separator: "/").map(String.init)
    }

    func rawPath(from components: [String]) -> String {
        if components == [""] {
            return "/"
        }
        return "/" + components.joined(separator: "/")
    }

    func documentContainsPath(_ rawValue: String) -> Bool {
        plan.document.paths[OpenAPI.Path(rawValue: rawValue)] != nil
    }
}
