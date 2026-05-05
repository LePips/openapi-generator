import Foundation
import OpenAPIGeneratorCore
import Testing

@Suite(.serialized, .snapshots(record: .missing))
struct SnapshotTests {

    @Test
    func `petstore default`() throws {
        try DirectorySnapshot.assert(
            named: "petstore-default",
            spec: "petstore.yaml"
        )
    }

    @Test
    func `cookpad default`() throws {
        try DirectorySnapshot.assert(
            named: "cookpad-default",
            spec: "cookpad.json"
        )
    }

    @Test
    func `petstore entities only`() throws {
        var config = Configuration()
        config.generate = [.entities]

        try DirectorySnapshot.assert(
            named: "petstore-entities-only",
            spec: "petstore.yaml",
            config: config
        )
    }

    @Test
    func `petstore custom imports`() throws {
        var config = Configuration()
        config.paths.imports = ["Foundation", "Get", "HTTPHeaders", "CoreData"]
        config.entities.imports = ["CoreLocation"]

        try DirectorySnapshot.assert(
            named: "petstore-custom-imports",
            spec: "petstore.yaml",
            config: config
        )
    }

    @Test
    func `petstore disable comments`() throws {
        var config = Configuration()
        config.comments.options = []

        try DirectorySnapshot.assert(
            named: "petstore-disable-comments",
            spec: "petstore.yaml",
            config: config
        )
    }

    @Test
    func `petstore internal access`() throws {
        var config = Configuration()
        config.access = .internal

        try DirectorySnapshot.assert(
            named: "petstore-internal-access",
            spec: "petstore.yaml",
            config: config
        )
    }

    @Test
    func `petstore entity name template`() throws {
        var config = Configuration()
        config.entities.nameTemplate = "%0Generated"

        try DirectorySnapshot.assert(
            named: "petstore-entity-name-template",
            spec: "petstore.yaml",
            config: config
        )
    }

    @Test
    func `petstore entity filename template`() throws {
        var config = Configuration()
        config.entities.filenameTemplate = "Models/%0Model.swift"

        try DirectorySnapshot.assert(
            named: "petstore-entity-filename-template",
            spec: "petstore.yaml",
            config: config
        )
    }

    @Test
    func `petstore sort properties alphabetically`() throws {
        var config = Configuration()
        config.entities.sortProperties = true

        try DirectorySnapshot.assert(
            named: "petstore-sort-properties-alphabetically",
            spec: "petstore.yaml",
            config: config
        )
    }

    @Test
    func `config file header`() throws {
        var config = entityConfig()
        config.fileHeader = "// Custom File Header"

        try assertConfigEntitySnapshot(named: "config-file-header", config: config)
    }

    @Test
    func `config comment options`() throws {
        var config = entityConfig()
        config.comments.options = [.description]

        try assertConfigEntitySnapshot(named: "config-comment-options", config: config)
    }

    @Test
    func `config deprecation comment`() throws {
        var config = entityConfig()
        config.comments.annotateDeprecations = .comment

        try assertConfigEntitySnapshot(named: "config-deprecation-comment", config: config)
    }

    @Test
    func `config deprecation none`() throws {
        var config = entityConfig()
        config.comments.annotateDeprecations = .none

        try assertConfigEntitySnapshot(named: "config-deprecation-none", config: config)
    }

    @Test
    func `config deprecation remove properties`() throws {
        var config = Configuration()
        config.comments.annotateDeprecations = .remove
        config.extensions.emit = []
        config.generate = [.entities]

        try DirectorySnapshot.assert(
            named: "config-deprecation-remove-properties",
            spec: "config-deprecation-remove.yaml",
            config: config,
            fileFilter: ["Entities/Widget.swift"]
        )
    }

    @Test
    func `config deprecation remove entities`() throws {
        var config = Configuration()
        config.comments.annotateDeprecations = .remove
        config.extensions.emit = []
        config.generate = [.entities]

        try DirectorySnapshot.assert(
            named: "config-deprecation-remove-entities",
            spec: "config-deprecation-remove.yaml",
            config: config,
            fileFilter: ["Entities/Widget.swift", "Entities/DeprecatedWidget.swift"]
        )
    }

    @Test
    func `config deprecation remove entities and properties`() throws {
        var config = Configuration()
        config.comments.annotateDeprecations = .remove
        config.extensions.emit = []
        config.generate = [.entities]

        try DirectorySnapshot.assert(
            named: "config-deprecation-remove-entities-and-properties",
            spec: "config-deprecation-remove.yaml",
            config: config
        )
    }

    @Test
    func `config data types`() throws {
        var config = entityConfig()
        config.dataTypes.integer = ["int32": "Int16", "int64": "Int"]
        config.dataTypes.number = ["float": "Float32"]
        config.dataTypes.string = ["date-time": "Instant", "uri": "URI"]

        try assertConfigEntitySnapshot(named: "config-data-types", config: config)
    }

    @Test
    func `config automatic identifiable`() throws {
        var config = entityConfig()
        config.entities.automaticIdentifiable = true

        try assertConfigEntitySnapshot(named: "config-automatic-identifiable", config: config)
    }

    @Test
    func `config coding strategy`() throws {
        var config = entityConfig()
        config.entities.codingStrategy = .codingKeys

        try assertConfigEntitySnapshot(named: "config-coding-strategy", config: config)
    }

    @Test
    func `config entity conformances`() throws {
        var config = entityConfig()
        config.entities.conformances = ["Codable", "Sendable"]

        try assertConfigEntitySnapshot(named: "config-entity-conformances", config: config)
    }

    @Test
    func `config entity imports empty`() throws {
        var config = entityConfig()
        config.entities.imports = []

        try assertConfigEntitySnapshot(named: "config-entity-imports-empty", config: config)
    }

    @Test
    func `config default values`() throws {
        var config = entityConfig()
        config.entities.defaultValues = false

        try assertConfigEntitySnapshot(named: "config-default-values", config: config)
    }

    @Test
    func `config entity type overrides`() throws {
        var config = entityConfig()
        config.entities.entityTypeOverrides = ["Widget": .finalClass]
        config.entities.mutableProperties = [.classes]

        try assertConfigEntitySnapshot(named: "config-entity-type-overrides", config: config)
    }

    @Test
    func `config entity property type overrides`() throws {
        var config = Configuration()
        config.entities.include = ["Pet"]
        config.entities.propertyTypeOverrides = ["Pet.tag": "UUID"]
        config.extensions.emit = []
        config.generate = [.entities]

        try DirectorySnapshot.assert(
            named: "config-entity-property-type-overrides",
            spec: "petstore.yaml",
            config: config,
            fileFilter: ["Entities/Pet.swift"]
        )
    }

    @Test
    func `config entity property type overrides generated property name`() throws {
        var config = entityConfig()
        config.entities.propertyTypeOverrides = ["Widget.isActive": "FeatureFlag"]

        try assertConfigEntitySnapshot(
            named: "config-entity-property-type-overrides-generated-property-name",
            config: config
        )
    }

    @Test
    func `config indirect properties`() throws {
        var config = entityConfig()
        config.entities.indirectProperties = ["Widget.metadata"]
        config.extensions.emit = [.indirect]

        try DirectorySnapshot.assert(
            named: "config-indirect-properties",
            spec: "config-entities.yaml",
            config: config,
            fileFilter: [
                "Entities/Widget.swift",
                "Extensions/Indirect.swift",
            ]
        )
    }

    @Test
    func `config enum conformances`() throws {
        var config = entityConfig()
        config.entities.enumConformances = ["Codable", "CaseIterable", "Sendable"]

        try assertConfigEntitySnapshot(named: "config-enum-conformances", config: config)
    }

    @Test
    func `config entity include`() throws {
        var config = entityConfig()
        config.entities.include = ["Ignored"]

        try DirectorySnapshot.assert(
            named: "config-entity-include",
            spec: "config-entities.yaml",
            config: config,
            fileFilter: ["Entities/Ignored.swift"]
        )
    }

    @Test
    func `config entity exclude`() throws {
        var config = Configuration()
        config.extensions.emit = []
        config.generate = [.entities]
        config.entities.exclude = [
            ComponentPath(parent: "Widget", child: nil),
        ]

        try DirectorySnapshot.assert(
            named: "config-entity-exclude",
            spec: "config-entity-excludes.yaml",
            config: config
        )
    }

    @Test
    func `config entity property exclude`() throws {
        var config = Configuration()
        config.entities.include = ["Widget"]
        config.extensions.emit = []
        config.generate = [.entities]
        config.entities.exclude = [
            ComponentPath(parent: "Widget", child: "currentProgram"),
        ]

        try DirectorySnapshot.assert(
            named: "config-entity-property-exclude",
            spec: "config-entity-excludes.yaml",
            config: config,
            fileFilter: ["Entities/Widget.swift"]
        )
    }

    @Test
    func `config entity property exclude by raw schema key`() throws {
        var config = Configuration()
        config.entities.include = ["Widget"]
        config.extensions.emit = []
        config.generate = [.entities]
        config.entities.exclude = [
            ComponentPath(parent: "Widget", child: "CurrentProgram"),
        ]

        try DirectorySnapshot.assert(
            named: "config-entity-property-exclude-raw-key",
            spec: "config-entity-excludes.yaml",
            config: config,
            fileFilter: ["Entities/Widget.swift"]
        )
    }

    @Test
    func `config memberwise init`() throws {
        var config = entityConfig()
        config.entities.memberwiseInit = false

        try assertConfigEntitySnapshot(named: "config-memberwise-init", config: config)
    }

    @Test
    func `config mutable properties`() throws {
        var config = entityConfig()
        config.entities.mutableProperties = []

        try assertConfigEntitySnapshot(named: "config-mutable-properties", config: config)
    }

    @Test
    func `config sort properties`() throws {
        var config = entityConfig()
        config.entities.sortProperties = false

        try assertConfigEntitySnapshot(named: "config-sort-properties", config: config)
    }

    @Test
    func `config string enums`() throws {
        var config = entityConfig()
        config.entities.stringEnums = false

        try assertConfigEntitySnapshot(named: "config-string-enums", config: config)
    }

    @Test
    func `config enum case renames`() throws {
        var config = entityConfig()
        config.rename.enumCases = ["Status.not-ready": "notReadyRenamed"]

        try assertConfigEntitySnapshot(named: "config-enum-case-renames", config: config)
    }

    @Test
    func `config property renames`() throws {
        var config = entityConfig()
        config.rename.properties = ["Widget.active": "enabled", "Widget.zeta": "zName"]

        try assertConfigEntitySnapshot(named: "config-property-renames", config: config)
    }

    @Test
    func `config path body type overrides`() throws {
        var config = pathConfig()
        config.paths.bodyTypeOverrides = ["application/json": "CreateWidgetBody"]

        try assertConfigPathSnapshot(named: "config-path-body-type-overrides", config: config)
    }

    @Test
    func `config path filename template`() throws {
        var config = pathConfig()
        config.paths.filenameTemplate = "Generated/%0Path.swift"

        try DirectorySnapshot.assert(
            named: "config-path-filename-template",
            spec: "config-paths.yaml",
            config: config,
            fileFilter: ["Paths/Generated/CreateWidgetPath.swift"]
        )
    }

    @Test
    func `config path unused URL query encoder import`() throws {
        var config = pathConfig(path: "/ignored")
        config.paths.imports = ["Get", "URLQueryEncoder"]

        try DirectorySnapshot.assert(
            named: "config-path-unused-url-query-encoder-import",
            spec: "config-paths.yaml",
            config: config,
            fileFilter: ["Paths/Ignored.swift"]
        )
    }

    @Test
    func `config path imports`() throws {
        var config = pathConfig()
        config.paths.imports = ["CustomNetworking", "Get"]

        try assertConfigPathSnapshot(named: "config-path-imports", config: config)
    }

    @Test
    func `config path imports empty`() throws {
        var config = pathConfig(path: "/ignored")
        config.paths.imports = []

        try DirectorySnapshot.assert(
            named: "config-path-imports-empty",
            spec: "config-paths.yaml",
            config: config,
            fileFilter: ["Paths/Ignored.swift"]
        )
    }

    @Test
    func `config path include`() throws {
        let config = pathConfig(path: "/ignored")

        try DirectorySnapshot.assert(
            named: "config-path-include",
            spec: "config-paths.yaml",
            config: config,
            fileFilter: ["Paths/Ignored.swift"]
        )
    }

    @Test
    func `config path deprecation annotation`() throws {
        let config = pathConfig(path: "/legacy")

        try DirectorySnapshot.assert(
            named: "config-path-deprecation-annotation",
            spec: "config-path-deprecated.yaml",
            config: config,
            fileFilter: ["Paths/GetLegacyItem.swift"]
        )
    }

    @Test
    func `config path deprecation comment`() throws {
        var config = pathConfig(path: "/legacy")
        config.comments.annotateDeprecations = .comment

        try DirectorySnapshot.assert(
            named: "config-path-deprecation-comment",
            spec: "config-path-deprecated.yaml",
            config: config,
            fileFilter: ["Paths/GetLegacyItem.swift"]
        )
    }

    @Test
    func `config path deprecation none`() throws {
        var config = pathConfig(path: "/legacy")
        config.comments.annotateDeprecations = .none

        try DirectorySnapshot.assert(
            named: "config-path-deprecation-none",
            spec: "config-path-deprecated.yaml",
            config: config,
            fileFilter: ["Paths/GetLegacyItem.swift"]
        )
    }

    @Test
    func `config path deprecation remove`() throws {
        var config = Configuration()
        config.comments.annotateDeprecations = .remove
        config.extensions.emit = []
        config.generate = [.paths]

        try DirectorySnapshot.assert(
            named: "config-path-deprecation-remove",
            spec: "config-deprecation-remove.yaml",
            config: config
        )
    }

    @Test
    func `config inline query parameter limit`() throws {
        var config = pathConfig()
        config.paths.inlineQueryParameterLimit = nil

        try assertConfigPathSnapshot(named: "config-inline-query-parameter-limit", config: config)
    }

    @Test
    func `config inline simple requests`() throws {
        var config = pathConfig()
        config.paths.inlineSimpleRequests = false

        try assertConfigPathSnapshot(named: "config-inline-simple-requests", config: config)
    }

    @Test
    func `config path response type overrides`() throws {
        var config = pathConfig()
        config.paths.responseTypeOverrides = ["WidgetResponse": "WidgetEnvelope"]

        try assertConfigPathSnapshot(named: "config-path-response-type-overrides", config: config)
    }

    @Test
    func `config operation renames`() throws {
        var config = pathConfig()
        config.rename.operations = ["createWidget": "makeWidget"]

        try DirectorySnapshot.assert(
            named: "config-operation-renames",
            spec: "config-paths.yaml",
            config: config,
            fileFilter: ["Paths/MakeWidget.swift"]
        )
    }

    @Test
    func `config parameter renames`() throws {
        var config = pathConfig()
        config.rename.parameters = ["expand": "expanded"]

        try assertConfigPathSnapshot(named: "config-parameter-renames", config: config)
    }

    @Test
    func `config access`() throws {
        var config = helperConfig()
        config.access = .internal

        try assertPathsNamespaceSnapshot(named: "config-access", config: config)
    }

    @Test
    func `config extensions emit`() throws {
        var config = helperConfig()
        config.extensions.emit = [.info]

        try DirectorySnapshot.assert(
            named: "config-extensions-emit",
            spec: "config-helpers.yaml",
            config: config,
            fileFilter: ["Extensions/Info.swift"]
        )
    }

    @Test
    func `config info full`() throws {
        var config = helperConfig()
        config.extensions.emit = [.info]

        try DirectorySnapshot.assert(
            named: "config-info-full",
            spec: "config-info-full.yaml",
            config: config,
            fileFilter: ["Extensions/Info.swift"]
        )
    }

    @Test
    func `config info name`() throws {
        var config = helperConfig()
        config.extensions.emit = [.info]
        config.extensions.infoName = "APIInfo"

        try DirectorySnapshot.assert(
            named: "config-info-name",
            spec: "config-info-full.yaml",
            config: config,
            fileFilter: ["Extensions/APIInfo.swift"]
        )
    }

    @Test
    func `config paths namespace`() throws {
        var config = helperConfig()
        config.paths.namespace = "APIRoutes"

        try DirectorySnapshot.assert(
            named: "config-paths-namespace",
            spec: "config-helpers.yaml",
            config: config,
            fileFilter: ["Extensions/APIRoutes.swift"]
        )
    }

    @Test
    func `config package`() throws {
        var config = Configuration()
        config.generate = [.entities, .paths, .package]
        config.module = "GeneratedAPI"

        try DirectorySnapshot.assert(
            named: "config-package",
            spec: "petstore.yaml",
            config: config
        )
    }

    @Test
    func `config package requires module`() throws {
        var config = Configuration()
        config.generate = [.package]
        config.module = ""

        do {
            try DirectorySnapshot.assert(
                named: "config-package-requires-module",
                spec: "config-helpers.yaml",
                config: config
            )
            Issue.record("Expected package generation to fail when module is empty.")
        } catch let error as GeneratorError {
            #expect(error.message.contains("module"))
        }
    }
}

func entityConfig() -> Configuration {
    var config = Configuration()
    config.entities.include = ["Widget"]
    config.extensions.emit = []
    config.generate = [.entities]
    return config
}

func pathConfig(path: String = "/widgets/{widgetId}") -> Configuration {
    var config = Configuration()
    config.extensions.emit = []
    config.generate = [.paths]
    config.paths.include = [path]
    return config
}

func helperConfig() -> Configuration {
    var config = Configuration()
    config.extensions.emit = [.pathsNamespace]
    config.generate = []
    return config
}

private func assertConfigEntitySnapshot(named name: String, config: Configuration) throws {
    try DirectorySnapshot.assert(
        named: name,
        spec: "config-entities.yaml",
        config: config,
        fileFilter: ["Entities/Widget.swift"]
    )
}

private func assertConfigPathSnapshot(named name: String, config: Configuration) throws {
    try DirectorySnapshot.assert(
        named: name,
        spec: "config-paths.yaml",
        config: config,
        fileFilter: ["Paths/CreateWidget.swift"]
    )
}

private func assertPathsNamespaceSnapshot(named name: String, config: Configuration) throws {
    try DirectorySnapshot.assert(
        named: name,
        spec: "config-helpers.yaml",
        config: config,
        fileFilter: ["Extensions/Paths.swift"]
    )
}
