@testable import OpenAPIGeneratorCore
import Testing

struct SwiftyNamingTests {
    @Test(arguments: [
        ("ResetPassword", "isResetPassword"),
        ("ResetURL", "isResetURL"),
        ("URLAvailable", "isURLAvailable"),
        ("enabled", "isEnabled"),
        ("isEnabled", "isEnabled"),
        ("canDownload", "canDownload"),
        ("shouldResetPassword", "shouldResetPassword"),
    ])
    func `swifty renaming`(rawName: String, expectedName: String) {
        let resolver = NameResolver(config: .init())
        let name = resolver
            .property(rawName)
            .asBoolean(acronyms: Configuration.defaultAcronyms)
            .rawValue

        #expect(name == expectedName)
    }
}
