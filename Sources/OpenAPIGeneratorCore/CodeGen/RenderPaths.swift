import Foundation

extension CodeGen {
    func renderOperation(_ declaration: PathOp) -> String {
        renderPathExtension(of: plan.config.paths.namespace, contents: renderPathMember(declaration))
    }

    func renderPathExtension(of namespace: String, contents: String) -> String {
        """
        extension \(namespace) {
        \(contents.indented)
        }
        """
    }

    func renderPathMember(_ declaration: PathOp) -> String {
        let comments = operationComments(
            summary: declaration.summary,
            description: declaration.description,
            isDeprecated: declaration.isDeprecated
        )
        let params = declaration.parameters.map(\.signature).joined(separator: ", ")
        let ownership = declaration.isStatic ? "static " : ""
        let signature = if params.isEmpty {
            "\(access)\(ownership)var \(declaration.name.rawValue): Request<\(declaration.responseType)>"
        } else {
            "\(access)\(ownership)func \(declaration.name.rawValue)(\(params)) -> Request<\(declaration.responseType)>"
        }
        let member = """
        \(comments)\(signature) {
        \(declaration.requestExpression.indented)
        }
        """
        let nested = declaration.nested.map { nested -> String in
            (try? render(nested)) ?? ""
        }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        return [member, nested].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}
