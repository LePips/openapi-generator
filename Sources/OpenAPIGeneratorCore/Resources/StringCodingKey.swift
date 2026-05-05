import Foundation

struct StringCodingKey: CodingKey, ExpressibleByStringLiteral {
    private let string: String
    private var int: Int?

    var stringValue: String {
        string
    }

    init(string: String) {
        self.string = string
    }

    init?(stringValue: String) {
        string = stringValue
    }

    var intValue: Int? {
        int
    }

    init?(intValue: Int) {
        string = String(describing: intValue)
        int = intValue
    }

    init(stringLiteral value: String) {
        string = value
    }
}
