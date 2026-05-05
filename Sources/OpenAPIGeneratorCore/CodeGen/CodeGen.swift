import Foundation
import OpenAPIKit30

public final class CodeGen {
    let plan: GenerationPlan
    let names: NameResolver
    var state = BuildState()

    public init(plan: GenerationPlan) {
        self.plan = plan
        names = NameResolver(config: plan.config)
    }

    public func generate() throws -> GeneratedSourceBundle {
        var files: [GeneratedFile] = []
        if plan.config.generate.contains(.entities) {
            files += try entityFiles()
        }
        if plan.config.generate.contains(.paths) {
            files += try pathFiles()
        }
        files += try promotedFiles()
        return GeneratedSourceBundle(files: files, usage: state.usage)
    }
}

struct BuildState {
    var usage = GenerationUsage()
    var decls = DeclStore()
    var madeSchemas: [TypeName: EntityDecl] = [:]
    var topLevelTypes = Set<TypeName>()
    var fileTypes = Set<TypeName>()
}
