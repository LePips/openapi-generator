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
        var entityJobs: [EntityFileJob] = []
        var pathJobs: [PathFileJob] = []

        if plan.config.generate.contains(.entities) {
            entityJobs = try entityFileJobs()
        }
        if plan.config.generate.contains(.paths) {
            pathJobs = try pathFileJobs()
        }

        try applySharedShapeDeduplication(entityJobs: &entityJobs, pathJobs: &pathJobs)

        files += try renderEntityFiles(entityJobs)
        files += try renderPathFiles(pathJobs)
        return GeneratedSourceBundle(files: files, usage: state.usage)
    }
}

struct EntityFileJob {
    var name: TypeName
    var declaration: SwiftDecl
    var isShared = false
}

enum PathFileJob {
    case operation(OperationPathFileJob)
    case rest(RestPathFileJob)
}

struct OperationPathFileJob {
    let filename: String
    var declaration: PathOp
}

struct RestPathFileJob {
    let job: CodeGen.RestPathJob
    var operations: [PathOp]
}

struct BuildState {
    var usage = GenerationUsage()
    var madeSchemas: [TypeName: EntityDecl] = [:]
    var topLevelTypes = Set<TypeName>()
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
