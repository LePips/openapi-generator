import Foundation
import OpenAPIKit30

extension CodeGen {
    func operationPathFiles() throws -> [GeneratedFile] {
        let operations = try plan.document.paths.flatMap { path, item -> [(OpenAPI.Path, OpenAPI.PathItem, String, OpenAPI.Operation)] in
            guard shouldGeneratePath(path.rawValue) else { return [] }
            let resolved = try item.unwrapped(in: plan.document)
            return resolved.allOperations.map { method, operation in (path, resolved, method, operation) }
        }

        return try operations.compactMap { path, item, method, operation in
            guard !shouldRemoveDeprecated(operation.deprecated) else { return nil }
            let operationID = plan.config.rename.operations[operation.operationId ?? ""] ?? (operation.operationId ?? "")
            guard !operationID.isEmpty else { throw GeneratorError("OperationId is invalid or missing for \(path.rawValue)") }
            let declaration = try makeOperation(
                path: path,
                item: item,
                method: method,
                operation: operation,
                operationID: operationID,
                baseName: names.type(operationID),
                memberName: names.property(operationID),
                isStatic: true,
                usesStoredPath: false
            )
            let filename = names.type(operationID).rawValue
            let body = renderOperation(declaration)
            let source = sourceFile(imports: pathImports(), body: body)
            return GeneratedFile(relativePath: "Paths/\(template(plan.config.paths.filenameTemplate, filename))", contents: source)
        }
    }
}
