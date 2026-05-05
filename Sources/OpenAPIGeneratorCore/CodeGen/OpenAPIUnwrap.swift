import Foundation
import OpenAPIKit30

extension Either where A == JSONReference<JSONSchema>, B == JSONSchema {
    func unwrapped(in spec: OpenAPI.Document) throws -> JSONSchema {
        switch self {
        case let .a(reference):
            try reference.dereferenced(in: spec.components).jsonSchema
        case let .b(schema):
            schema
        }
    }
}

extension Either where A == JSONReference<OpenAPI.Parameter>, B == OpenAPI.Parameter {
    func unwrapped(in spec: OpenAPI.Document) throws -> OpenAPI.Parameter {
        switch self {
        case let .a(reference):
            try reference.dereferenced(in: spec.components).underlyingParameter
        case let .b(value):
            value
        }
    }
}

extension Either where A == JSONReference<OpenAPI.Request>, B == OpenAPI.Request {
    func unwrapped(in spec: OpenAPI.Document) throws -> OpenAPI.Request {
        switch self {
        case let .a(reference):
            guard let name = reference.name,
                  let key = OpenAPI.ComponentKey(rawValue: name),
                  let request = spec.components.requestBodies[key]
            else {
                throw GeneratorError("Failed to find request body \(reference)")
            }
            return request
        case let .b(request):
            return request
        }
    }
}

extension Either where A == JSONReference<OpenAPI.PathItem>, B == OpenAPI.PathItem {
    func unwrapped(in spec: OpenAPI.Document) throws -> OpenAPI.PathItem {
        switch self {
        case let .a(reference):
            try reference.dereferenced(in: spec.components).underlyingPathItem
        case let .b(value):
            value
        }
    }
}

extension OpenAPI.Parameter {
    func unwrapped(in _: OpenAPI.Document) throws -> OpenAPI.Parameter.SchemaContext {
        switch schemaOrContent {
        case let .a(schema):
            return schema
        case .b:
            throw GeneratorError("Parameter content map not supported for \(name)")
        }
    }
}

extension OpenAPI.Operation {
    var firstSuccessfulResponse: Either<JSONReference<OpenAPI.Response>, OpenAPI.Response>? {
        if let response = responses.first(where: { key, value in
            key.isSuccess && !(value.responseValue?.content.values.isEmpty ?? true)
        })?.value {
            return response
        }
        if let response = responses.first(where: { $0.key.isSuccess })?.value {
            return response
        }
        return responses.first { $0.key == .default }?.value
    }
}

extension OpenAPI.PathItem {
    var allOperations: [(String, OpenAPI.Operation)] {
        [
            get.map { ("get", $0) },
            post.map { ("post", $0) },
            put.map { ("put", $0) },
            patch.map { ("patch", $0) },
            delete.map { ("delete", $0) },
            options.map { ("options", $0) },
            head.map { ("head", $0) },
            trace.map { ("trace", $0) },
        ].compactMap(\.self)
    }
}
