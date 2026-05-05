import Foundation
import OpenAPIKit30
import Yams

public struct FileDecoder<T: Decodable> {

    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() throws -> T {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw GeneratorError("Unable to read file at \(url.path). \(error)")
        }

        do {
            if url.pathExtension.lowercased() == "json" {
                let decoder = JSONDecoder()
                decoder.userInfo[VendorExtensionsConfiguration.enabledKey] = false
                return try decoder.decode(T.self, from: data)
            } else {
                return try YAMLDecoder().decode(T.self, from: data)
            }
        } catch {
            throw GeneratorError("Expected file at \(url.path) to decode file. \(error)")
        }
    }
}
