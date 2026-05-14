import Foundation
import OpenAPIKit30

extension CodeGen {
    func applySharedShapeDeduplication(entityJobs: inout [EntityFileJob], pathJobs: inout [PathFileJob]) throws {
        guard !plan.config.entities.sharedShapeTypes.isEmpty else { return }

        let records = collectShapeRecords(entityJobs: entityJobs, pathJobs: pathJobs)
        let signaturesByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, shapeSignature(for: $0.declaration)) })
        let recordsBySignature = Dictionary(grouping: records) { signaturesByID[$0.id]! }
        let duplicatePools = recordsBySignature.filter { $0.value.count > 1 }
        guard !duplicatePools.isEmpty else { return }

        var configuredPools: [ShapeSignature: TypeName] = [:]
        var configuredRepresentatives: [ShapeSignature: EntityDecl] = [:]
        for (key, value) in plan.config.entities.sharedShapeTypes.sorted(by: { $0.key < $1.key }) {
            let matchedRecords = matchedRecords(for: key, records: records, signaturesByID: signaturesByID)
            let signatures = Set(matchedRecords.compactMap { signaturesByID[$0.id] })
                .filter { duplicatePools[$0] != nil }
            guard signatures.count == 1, let signature = signatures.first else { continue }

            let sharedName = names.type(value)
            if let existing = configuredPools[signature], existing != sharedName {
                throw GeneratorError(
                    "Conflicting shared shape type names for duplicate shape: \(existing.rawValue) and \(sharedName.rawValue)."
                )
            }
            configuredPools[signature] = sharedName
            configuredRepresentatives[signature] = matchedRecords.sorted(by: { $0.qualifiedName < $1.qualifiedName })[0].declaration
        }

        guard !configuredPools.isEmpty else { return }

        var objectReplacements: [ObjectIdentifier: TypeName] = [:]
        var topLevelReplacements: [TypeName: TypeName] = [:]
        var sharedRepresentatives: [(sharedName: TypeName, declaration: EntityDecl)] = []

        for (signature, sharedName) in configuredPools.sorted(by: { $0.value.rawValue < $1.value.rawValue }) {
            guard let pool = duplicatePools[signature] else { continue }
            for record in pool {
                objectReplacements[record.id] = sharedName
                if record.isTopLevel {
                    topLevelReplacements[record.name] = sharedName
                }
            }
            let representative = configuredRepresentatives[signature]
                ?? pool.sorted(by: { $0.qualifiedName < $1.qualifiedName })[0].declaration
            sharedRepresentatives.append((sharedName, representative))
        }

        for index in entityJobs.indices {
            entityJobs[index].declaration = rewriteDeclaration(
                entityJobs[index].declaration,
                objectReplacements: objectReplacements,
                topLevelReplacements: topLevelReplacements
            ) ?? entityJobs[index].declaration
        }

        for index in pathJobs.indices {
            pathJobs[index] = rewritePathJob(
                pathJobs[index],
                objectReplacements: objectReplacements,
                topLevelReplacements: topLevelReplacements
            )
        }

        entityJobs.removeAll { job in
            guard !job.isShared, let entity = job.declaration as? EntityDecl else { return false }
            return objectReplacements[ObjectIdentifier(entity)] != nil
        }

        let sharedJobs = sharedRepresentatives.map { sharedName, representative in
            let declaration = cloneEntity(representative, named: sharedName)
            return EntityFileJob(name: sharedName, declaration: declaration, isShared: true)
        }
        entityJobs += sharedJobs
        state.topLevelTypes.formUnion(sharedJobs.map(\.name))
    }
}

private struct ShapeRecord {
    let id: ObjectIdentifier
    let name: TypeName
    let qualifiedName: String
    let declaration: EntityDecl
    let isTopLevel: Bool
}

private struct ShapeSignature: Hashable {
    var declaration: String
    var properties: [PropertySignature]
}

private struct PropertySignature: Hashable {
    var name: String
    var type: String
    var isOptional: Bool
    var key: String
    var explode: Bool
    var style: String?
    var defaultValue: String?
    var isIndirect: Bool
}

private extension CodeGen {
    func collectShapeRecords(entityJobs: [EntityFileJob], pathJobs: [PathFileJob]) -> [ShapeRecord] {
        var records: [ShapeRecord] = []

        for job in entityJobs {
            collectShapeRecords(
                from: job.declaration,
                qualifiedName: job.name.rawValue,
                isTopLevel: true,
                into: &records
            )
        }

        for job in pathJobs {
            switch job {
            case let .operation(job):
                for declaration in job.declaration.nested {
                    collectShapeRecords(
                        from: declaration,
                        qualifiedName: "\(plan.config.paths.namespace).\(declaration.name.rawValue)",
                        isTopLevel: false,
                        into: &records
                    )
                }
            case let .rest(job):
                let prefix = restPathQualifiedPrefix(for: job.job)
                for operation in job.operations {
                    for declaration in operation.nested {
                        collectShapeRecords(
                            from: declaration,
                            qualifiedName: "\(prefix).\(declaration.name.rawValue)",
                            isTopLevel: false,
                            into: &records
                        )
                    }
                }
            }
        }

        return records
    }

    func collectShapeRecords(
        from declaration: SwiftDecl,
        qualifiedName: String,
        isTopLevel: Bool,
        into records: inout [ShapeRecord]
    ) {
        if let entity = declaration as? EntityDecl {
            if isEligibleForShapeDeduplication(entity) {
                records.append(ShapeRecord(
                    id: ObjectIdentifier(entity),
                    name: entity.name,
                    qualifiedName: qualifiedName,
                    declaration: entity,
                    isTopLevel: isTopLevel
                ))
            }
            for nested in entity.nested {
                collectShapeRecords(
                    from: nested,
                    qualifiedName: "\(qualifiedName).\(nested.name.rawValue)",
                    isTopLevel: false,
                    into: &records
                )
            }
        } else if let alias = declaration as? TypealiasDecl, let nested = alias.nested {
            collectShapeRecords(
                from: nested,
                qualifiedName: "\(qualifiedName).\(nested.name.rawValue)",
                isTopLevel: false,
                into: &records
            )
        }
    }

    func isEligibleForShapeDeduplication(_ entity: EntityDecl) -> Bool {
        switch entity.kind {
        case .object, .allOf:
            true
        case .anyOf, .oneOf:
            false
        }
    }

    func shapeSignature(for entity: EntityDecl) -> ShapeSignature {
        ShapeSignature(
            declaration: [
                String(describing: entity.kind),
                entity.isForm.description,
                entity.isRenderedAsStruct.description,
                resolveType(for: entity),
                entity.protocols.joined(separator: ","),
            ].joined(separator: "|"),
            properties: entity.properties.map { property in
                PropertySignature(
                    name: property.name.rawValue,
                    type: typeSignature(for: property.type),
                    isOptional: property.isOptional,
                    key: property.key,
                    explode: property.explode,
                    style: property.style.map(String.init(describing:)),
                    defaultValue: property.defaultValue,
                    isIndirect: property.isIndirect
                )
            }
        )
    }

    func typeSignature(for type: SwiftType) -> String {
        switch type {
        case let .builtin(name):
            "builtin:\(name.rawValue)"
        case let .userDefined(name):
            "user:\(name.rawValue)"
        case let .array(element):
            "array:\(typeSignature(for: element))"
        case let .dictionary(key, value):
            "dictionary:\(typeSignature(for: key)):\(typeSignature(for: value))"
        }
    }

    func matchedRecords(
        for key: String,
        records: [ShapeRecord],
        signaturesByID: [ObjectIdentifier: ShapeSignature]
    ) -> [ShapeRecord] {
        let exact = records.filter { $0.qualifiedName == key }
        if !exact.isEmpty {
            return exact
        }

        guard !key.contains(".") else { return [] }
        let bare = records.filter { $0.name.rawValue == key }
        let signatures = Set(bare.compactMap { signaturesByID[$0.id] })
        return signatures.count == 1 ? bare : []
    }

    func restPathQualifiedPrefix(for job: RestPathJob) -> String {
        let parentTypes = Array(job.types.suffix(job.components.count)).dropLast()
        return ([plan.config.paths.namespace] + parentTypes.map(\.rawValue) + [job.type.rawValue]).joined(separator: ".")
    }
}

private extension CodeGen {
    func rewritePathJob(
        _ job: PathFileJob,
        objectReplacements: [ObjectIdentifier: TypeName],
        topLevelReplacements: [TypeName: TypeName]
    ) -> PathFileJob {
        switch job {
        case var .operation(job):
            job.declaration = rewritePathOp(
                job.declaration,
                objectReplacements: objectReplacements,
                topLevelReplacements: topLevelReplacements
            )
            return .operation(job)
        case var .rest(job):
            job.operations = job.operations.map {
                rewritePathOp(
                    $0,
                    objectReplacements: objectReplacements,
                    topLevelReplacements: topLevelReplacements
                )
            }
            return .rest(job)
        }
    }

    func rewritePathOp(
        _ operation: PathOp,
        objectReplacements: [ObjectIdentifier: TypeName],
        topLevelReplacements: [TypeName: TypeName]
    ) -> PathOp {
        let localReplacements = localReplacements(in: operation.nested, objectReplacements: objectReplacements)
        let nested = operation.nested.compactMap {
            rewriteDeclaration(
                $0,
                objectReplacements: objectReplacements,
                topLevelReplacements: topLevelReplacements,
                localReplacements: localReplacements
            )
        }
        let allReplacements = topLevelReplacements.merging(localReplacements) { _, local in local }
        let requestExpression = rewriteTypeConstructors(operation.requestExpression, replacements: allReplacements)

        return PathOp(
            name: operation.name,
            isStatic: operation.isStatic,
            summary: operation.summary,
            description: operation.description,
            isDeprecated: operation.isDeprecated,
            responseType: rewriteSwiftType(
                operation.responseType,
                topLevelReplacements: topLevelReplacements,
                localReplacements: localReplacements
            ),
            parameters: operation.parameters.map { parameter in
                FuncParam(
                    label: parameter.label,
                    externalName: parameter.externalName,
                    type: rewriteSwiftType(
                        parameter.type,
                        topLevelReplacements: topLevelReplacements,
                        localReplacements: localReplacements
                    ),
                    defaultValue: parameter.defaultValue,
                    isOptional: parameter.isOptional
                )
            },
            requestExpression: requestExpression,
            nested: nested
        )
    }

    func rewriteDeclaration(
        _ declaration: SwiftDecl,
        objectReplacements: [ObjectIdentifier: TypeName],
        topLevelReplacements: [TypeName: TypeName],
        localReplacements: [TypeName: TypeName] = [:]
    ) -> SwiftDecl? {
        if let entity = declaration as? EntityDecl {
            rewriteEntity(
                entity,
                objectReplacements: objectReplacements,
                topLevelReplacements: topLevelReplacements,
                localReplacements: localReplacements
            )
            return objectReplacements[ObjectIdentifier(entity)] == nil ? entity : nil
        }

        if var alias = declaration as? TypealiasDecl {
            alias.type = rewriteSwiftType(
                alias.type,
                topLevelReplacements: topLevelReplacements,
                localReplacements: localReplacements
            )
            if let nested = alias.nested {
                alias.nested = rewriteDeclaration(
                    nested,
                    objectReplacements: objectReplacements,
                    topLevelReplacements: topLevelReplacements,
                    localReplacements: localReplacements
                )
            }
            return alias
        }

        return declaration
    }

    func rewriteEntity(
        _ entity: EntityDecl,
        objectReplacements: [ObjectIdentifier: TypeName],
        topLevelReplacements: [TypeName: TypeName],
        localReplacements inheritedLocalReplacements: [TypeName: TypeName]
    ) {
        let nestedLocalReplacements = inheritedLocalReplacements.merging(
            localReplacements(in: entity.nested, objectReplacements: objectReplacements)
        ) { _, nested in nested }

        for index in entity.properties.indices {
            var property = entity.properties[index]
            if let nested = property.nested {
                property.nested = rewriteDeclaration(
                    nested,
                    objectReplacements: objectReplacements,
                    topLevelReplacements: topLevelReplacements,
                    localReplacements: nestedLocalReplacements
                )
            }
            property.type = rewriteSwiftType(
                property.type,
                topLevelReplacements: topLevelReplacements,
                localReplacements: nestedLocalReplacements
            )
            entity.properties[index] = property
        }

        if let discriminator = entity.discriminator {
            entity.discriminator = Discriminator(
                propertyName: discriminator.propertyName,
                mapping: discriminator.mapping.mapValues {
                    rewriteSwiftType(
                        $0,
                        topLevelReplacements: topLevelReplacements,
                        localReplacements: nestedLocalReplacements
                    )
                },
                cases: discriminator.cases
            )
        }
    }

    func localReplacements(
        in declarations: [SwiftDecl],
        objectReplacements: [ObjectIdentifier: TypeName]
    ) -> [TypeName: TypeName] {
        var replacements: [TypeName: TypeName] = [:]
        for declaration in declarations {
            if let entity = declaration as? EntityDecl,
               let replacement = objectReplacements[ObjectIdentifier(entity)]
            {
                replacements[entity.name] = replacement
            }
        }
        return replacements
    }

    func rewriteSwiftType(
        _ type: SwiftType,
        topLevelReplacements: [TypeName: TypeName],
        localReplacements: [TypeName: TypeName]
    ) -> SwiftType {
        switch type {
        case let .builtin(name):
            .builtin(name)
        case let .userDefined(name):
            .userDefined(localReplacements[name] ?? topLevelReplacements[name] ?? name)
        case let .array(element):
            .array(rewriteSwiftType(
                element,
                topLevelReplacements: topLevelReplacements,
                localReplacements: localReplacements
            ))
        case let .dictionary(key, value):
            .dictionary(
                key: rewriteSwiftType(key, topLevelReplacements: topLevelReplacements, localReplacements: localReplacements),
                value: rewriteSwiftType(value, topLevelReplacements: topLevelReplacements, localReplacements: localReplacements)
            )
        }
    }

    func rewriteTypeConstructors(_ expression: String, replacements: [TypeName: TypeName]) -> String {
        replacements.reduce(expression) { output, item in
            output.replacingOccurrences(of: "\(item.key.rawValue)(", with: "\(item.value.rawValue)(")
        }
    }
}

private extension CodeGen {
    func cloneEntity(_ entity: EntityDecl, named name: TypeName) -> EntityDecl {
        let clone = EntityDecl(name: name, kind: entity.kind, metadata: entity.metadata, isForm: entity.isForm)
        clone.protocols = entity.protocols
        clone.properties = entity.properties.map(cloneProperty)
        clone.discriminator = entity.discriminator
        clone.isRenderedAsStruct = entity.isRenderedAsStruct
        return clone
    }

    func cloneProperty(_ property: Property) -> Property {
        var clone = property
        clone.nested = property.nested.map(cloneDeclaration)
        return clone
    }

    func cloneDeclaration(_ declaration: SwiftDecl) -> SwiftDecl {
        if let entity = declaration as? EntityDecl {
            return cloneEntity(entity, named: entity.name)
        }
        if let enumDecl = declaration as? StringEnumDecl {
            return enumDecl
        }
        if var alias = declaration as? TypealiasDecl {
            alias.nested = alias.nested.map(cloneDeclaration)
            return alias
        }
        if let function = declaration as? InlineFunctionDecl {
            return function
        }
        return declaration
    }
}
