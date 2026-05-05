import Foundation

extension String {
    var trimmedForSource: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var swiftStringLiteral: String {
        if contains(where: \.isNewline) {
            let delimiter = rawStringDelimiter(terminator: "\"\"\"", forceRaw: contains("\\"))
            return "\(delimiter)\"\"\"\n\(self)\n\"\"\"\(delimiter)"
        }
        if contains("\\") || contains("\"") {
            let delimiter = rawStringDelimiter(terminator: "\"", forceRaw: contains("\\"))
            return "\(delimiter)\"\(self)\"\(delimiter)"
        }
        return "\"\(self)\""
    }

    var indented: String {
        indented(count: 1)
    }

    func indented(count: Int) -> String {
        split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : String(repeating: " ", count: count * 4) + $0 }
            .joined(separator: "\n")
    }

    func commentLines(capitalized: Bool) -> String {
        let value = capitalized ? capitalizingFirstLetter() : self
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .map { "/// \($0)\n" }
            .joined()
    }

    func capitalizingFirstLetter() -> String {
        prefix(1).uppercased() + dropFirst()
    }

    func lowercasedFirstLetter() -> String {
        prefix(1).lowercased() + dropFirst()
    }

    var words: [String] {
        var output: [String] = []
        var remaining = self[...]
        while let index = remaining.firstIndex(where: { $0.isUppercase }) {
            output.append(String(remaining[..<index]))
            if !remaining.isEmpty {
                let start = remaining.startIndex
                remaining.replaceSubrange(start ... start, with: remaining[start].lowercased())
            }
            remaining = remaining[index...]
        }
        if !remaining.isEmpty {
            output.append(String(remaining))
        }
        return output.filter { !$0.isEmpty }
    }

    func process(isProperty: Bool, acronyms: [String]) -> String {
        NameProcessor(acronyms: acronyms).process(self, isProperty: isProperty)
    }

    fileprivate func process(isProperty: Bool, processor: NameProcessor) -> String {
        var components = sanitized.replacingOccurrences(of: "'", with: "")
            .components(separatedBy: badCharacters)
        if !components.contains(where: { $0.count > 1 && $0.contains(where: \.isLowercase) }) {
            components = components.map { $0.lowercased() }
        }
        var output = components.filter { !$0.isEmpty }.enumerated().map { index, string in
            if isProperty, index == 0 {
                return string.lowercasedFirstLetter()
            }
            return string.capitalizingFirstLetter()
        }.joined()
        guard let first = output.first else { return output }
        if !first.isLetter {
            output = (isProperty ? "_" : "__") + output
        }
        for acronym in processor.acronyms {
            if let range = output.range(of: acronym.capitalized),
               range.upperBound == output.endIndex || output[range.upperBound].isUppercase || output[range.upperBound] == "s"
            {
                output.replaceSubrange(range, with: acronym.uppercased)
            }
            if isProperty, output.lowercased().hasPrefix(acronym.rawValue) {
                output.replaceSubrange(
                    output.startIndex ..< output.index(output.startIndex, offsetBy: acronym.rawValue.count),
                    with: acronym.rawValue
                )
            }
        }
        if output == "self" {
            output = "this"
        }
        return isProperty ? output.escapedPropertyName : output.escapedTypeName
    }

    var sanitized: String {
        if let replacement = replacements[self] {
            return replacement
        }
        if last == ">" {
            return "\(dropLast())GreaterThan"
        }
        if last == "<" {
            return "\(dropLast())LessThan"
        }
        if first == "+" {
            return "plus\(dropFirst())"
        }
        if first == "-" {
            return "minus\(dropFirst())"
        }
        return self
    }

    var escapedPropertyName: String {
        keywords.contains(lowercased()) ? "`\(self)`" : self
    }

    var escapedTypeName: String {
        capitalizedKeywords.contains(self) ? "`\(self)`" : self
    }
}

struct NameProcessor {
    struct Acronym {
        let rawValue: String
        let capitalized: String
        let uppercased: String
    }

    let acronyms: [Acronym]

    init(acronyms: [String]) {
        self.acronyms = acronyms.map { acronym in
            Acronym(
                rawValue: acronym,
                capitalized: acronym.capitalizingFirstLetter(),
                uppercased: acronym.uppercased()
            )
        }
    }

    func process(_ rawValue: String, isProperty: Bool) -> String {
        rawValue.process(isProperty: isProperty, processor: self)
    }
}

private extension String {
    func rawStringDelimiter(terminator: String, forceRaw: Bool) -> String {
        var delimiter = forceRaw ? "#" : ""
        while contains("\(terminator)\(delimiter)") {
            delimiter += "#"
        }
        return delimiter
    }
}

extension CharacterSet {
    static let ticks = CharacterSet(charactersIn: "`")
}

extension Array {
    func removingDuplicates<U: Hashable>(by key: (Element) -> U) -> [Element] {
        var output: [Element] = []
        var seen = Set<U>()
        for element in self where seen.insert(key(element)).inserted {
            output.append(element)
        }
        return output
    }
}

extension [String] {
    func disambiguateDuplicateNames() -> [String] {
        var encountered: [String: Int] = [:]
        return map { name in
            let count = encountered[name] ?? 0
            encountered[name] = count + 1
            return count == 0 ? name : "\(name)\(count + 1)"
        }
    }
}

struct NameDeduplicator {
    private var encountered: [String: Int] = [:]

    mutating func add(name: String) -> String {
        let count = encountered[name] ?? 0
        encountered[name] = count + 1
        if count == 0 {
            return name
        }
        return add(name: "\(name)\(count + 1)")
    }
}

func singularized(_ value: String) -> String {
    if value.hasSuffix("ies") {
        return String(value.dropLast(3)) + "y"
    }
    if value.hasSuffix("ses") {
        return String(value.dropLast(2))
    }
    if value.hasSuffix("s"), value.count > 1 {
        return String(value.dropLast())
    }
    return value + "Item"
}

func pluralized(_ value: String) -> String {
    if value.hasSuffix("s") {
        return value
    }
    return value + "s"
}
