import Foundation
import OpenAPIKit30

public final class CodeGen {
    let plan: GenerationPlan
    let names: NameResolver
    var state: BuildState

    public init(plan: GenerationPlan) {
        self.plan = plan
        names = NameResolver(config: plan.config)
        state = BuildState(config: plan.config)
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
    var componentTypeNames: [String: TypeName] = [:]
    var referenceTypes: [ReferenceTypeCacheKey: SwiftType] = [:]
    let excludedEntities: Set<String>
    let excludedPropertiesByEntity: [String: Set<String>]

    init(config: Configuration) {
        excludedEntities = Set(config.entities.exclude.compactMap { $0.child == nil ? $0.parent : nil })

        var excludedPropertiesByEntity: [String: Set<String>] = [:]
        for path in config.entities.exclude {
            guard let child = path.child else { continue }
            excludedPropertiesByEntity[path.parent, default: []].insert(child)
        }
        self.excludedPropertiesByEntity = excludedPropertiesByEntity
    }
}

struct ReferenceTypeCacheKey: Hashable {
    let referenceName: String
    let namespace: String?
    let canInlineTypealias: Bool
}
