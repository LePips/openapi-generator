import Foundation

extension CodeGen {
    func renderOperation(_ declaration: PathOp) -> String {
        let comments = operationComments(
            summary: declaration.summary,
            description: declaration.description,
            isDeprecated: declaration.isDeprecated
        )
        let params = declaration.parameters.map(\.signature).joined(separator: ", ")
        let signature = if params.isEmpty {
            "\(access)static var \(declaration.name.rawValue): Request<\(declaration.responseType)>"
        } else {
            "\(access)static func \(declaration.name.rawValue)(\(params)) -> Request<\(declaration.responseType)>"
        }
        let member = """
        \(comments)\(signature) {
        \(declaration.requestExpression.indented)
        }
        """
        let nested = declaration.nested.map { nested -> String in
            (try? render(nested)) ?? ""
        }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        let body = [member, nested].filter { !$0.isEmpty }.joined(separator: "\n\n")
        return """
        extension \(plan.config.paths.namespace) {
        \(body.indented)
        }
        """
    }
}
