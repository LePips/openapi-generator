import Foundation

extension CodeGen {
    /// Writes promoted nested entity shapes as standalone files when they are shared or recursive.
    func promotedFiles() throws -> [GeneratedFile] {
        try state.decls.promotedEntries(excluding: state.fileTypes).map { entry in
            let relativePath = "Entities/\(template(plan.config.entities.filenameTemplate, entry.declaration.name.rawValue))"
            let source = try sourceFile(imports: plan.config.entities.imports, body: render(entry.declaration))
            return GeneratedFile(relativePath: relativePath, contents: source)
        }
    }

    func shouldPromote(_ declaration: SwiftDecl, context: MakeContext) -> Bool {
        declaration is EntityDecl && !context.parents.isEmpty
    }

    /// Keeps promoted declarations unique by name and shape before rendering a top-level file.
    func registerPromoted(_ declaration: SwiftDecl, context: MakeContext, source: String) throws -> SwiftType {
        _ = try state.decls.register(declaration, source: source, emit: true)
        let type = SwiftType.userDefined(declaration.name)
        if context.namespace != nil {
            return type.namespace(context.namespace)
        }
        return type
    }

    func sourceDescription(fallback: String, context: MakeContext) -> String {
        if let parent = context.parents.last?.name.rawValue {
            return "\(parent).\(fallback)"
        }
        if context.namespace == plan.config.module {
            return "operation support \(fallback)"
        }
        return fallback
    }
}

extension CodeGen {
    func sourceFile(imports: Set<String>, body: String) -> String {
        let importBlock = imports.sorted().map { "import \($0)" }.joined(separator: "\n")
        let normalizedBody = body.replacingOccurrences(of: "\(plan.config.module).\(plan.config.module).", with: "\(plan.config.module).")
        return [plan.config.fileHeader.trimmedForSource, importBlock, normalizedBody]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n") + "\n"
    }

    func render(_ declaration: SwiftDecl) throws -> String {
        switch declaration {
        case let declaration as StringEnumDecl:
            return renderStringEnum(declaration)
        case let declaration as EntityDecl:
            return try renderEntity(declaration)
        case let declaration as TypealiasDecl:
            return try renderTypealias(declaration)
        case let declaration as InlineFunctionDecl:
            return declaration.contents
        default:
            throw GeneratorError("Unsupported declaration \(declaration.name.rawValue)")
        }
    }

    func comments(for metadata: DeclarationMetadata, name: String) -> String {
        guard plan.config.commentsEnabled else { return "" }
        var output = ""
        var title = metadata.title ?? ""
        var description = metadata.description ?? ""
        if title == description {
            description = ""
        }
        if title.components(separatedBy: .whitespaces).joined().caseInsensitiveCompare(name) == .orderedSame {
            title = ""
        }
        if plan.config.comments.options.contains(.title), !title.isEmpty {
            output += title.commentLines(capitalized: plan.config.comments.options.contains(.capitalized))
        }
        if plan.config.comments.options.contains(.description), !description.isEmpty {
            if !output.isEmpty { output += "///\n" }
            output += description.commentLines(capitalized: plan.config.comments.options.contains(.capitalized))
        }
        if metadata.isDeprecated {
            switch plan.config.comments.annotateDeprecations {
            case .annotation:
                output += #"@available(*, deprecated, message: "Deprecated")"# + "\n"
            case .comment:
                if !output.isEmpty { output += "///\n" }
                output += "/// - Warning: Deprecated\n"
            case .none:
                break
            case .remove:
                break
            }
        }
        return output
    }

    func operationComments(summary: String?, description: String?, isDeprecated: Bool) -> String {
        var metadata = DeclarationMetadata.empty
        metadata.title = summary
        metadata.description = description
        metadata.isDeprecated = isDeprecated
        return comments(for: metadata, name: "")
    }

    var access: String {
        plan.config.access == .internal ? "" : "\(plan.config.access.rawValue) "
    }

    func shouldRemoveDeprecated(_ isDeprecated: Bool) -> Bool {
        plan.config.comments.annotateDeprecations == .remove && isDeprecated
    }
}
