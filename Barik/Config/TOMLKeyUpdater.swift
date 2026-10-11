import Foundation

/// Sets one string value in a TOML document by editing its text, so comments and formatting are kept. The key may be
/// written under any table on its path: `[widgets.default.time.popup]` with `view-variant = ...`, or
/// `[widgets.default.time]` with `popup.view-variant = ...`, and headers may have spaces or a trailing comment. A
/// document where the value cannot be set without restructuring it, such as one where the key is inside an inline
/// table, is reported as an error rather than rewritten into invalid TOML.
enum TOMLKeyUpdater {
    struct UnsupportedDocument: LocalizedError {
        let errorDescription: String?
    }

    static func updating(_ original: String, key: String, to newValue: String) throws -> String {
        let path = key.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard !path.contains(where: \.isEmpty) else {
            throw UnsupportedDocument(errorDescription: "Invalid key \"\(key)\"")
        }
        var lines = original.components(separatedBy: "\n")
        let document = Document(lines: lines)
        let quotedValue = quoted(newValue)

        try checkConflicts(in: document, for: path, key: key)

        let matches = document.keyValues.filter { $0.fullPath == path }
        if matches.count > 1 {
            throw UnsupportedDocument(errorDescription: "\"\(key)\" is set more than once")
        }
        if let match = matches.first {
            let comment = match.comment.map { " \($0)" } ?? ""
            lines.replaceSubrange(
                match.firstLine...match.lastLine, with: [match.keyAndEquals + " " + quotedValue + comment])
            return lines.joined(separator: "\n")
        }

        let parent = Array(path.dropLast())
        if let header = document.headers.last(where: { !$0.isArray && $0.path == parent }) {
            // The parent table has its own header: add the key after the table's last value.
            let last = document.keyValues.last { $0.firstLine > header.line && $0.lastLine < header.sectionEnd }
            lines.insert(
                (last?.indentation ?? "") + "\(bareOrQuoted(path.last!)) = \(quotedValue)",
                at: (last?.lastLine ?? header.line) + 1)
        } else if parent.isEmpty {
            let last = document.keyValues.last { $0.table.isEmpty }
            lines.insert("\(bareOrQuoted(path.last!)) = \(quotedValue)", at: (last?.lastLine ?? -1) + 1)
        } else if let sibling = document.keyValues.last(where: {
            $0.table.count < parent.count && $0.fullPath.starts(with: parent)
        }) {
            // The parent table is made by dotted keys, such as `popup.other = 1` under `[widgets.default.time]`. A
            // header for it would define the table twice, so add another dotted key next to them.
            let relativeKey = path.dropFirst(sibling.table.count).map(bareOrQuoted).joined(separator: ".")
            lines.insert(sibling.indentation + "\(relativeKey) = \(quotedValue)", at: sibling.lastLine + 1)
        } else {
            let header = "[\(parent.map(bareOrQuoted).joined(separator: "."))]"
            let insertion = ["", header, "\(bareOrQuoted(path.last!)) = \(quotedValue)"]
            // Keep the final newline of the file at the end.
            if lines.last == "" {
                lines.insert(contentsOf: insertion, at: lines.count - 1)
            } else {
                lines.append(contentsOf: insertion)
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Fails when the key's path is taken by something other than tables and the key itself: a value or inline table
    /// on the way (`popup = { ... }`), the key being a table, or an array of tables on the way.
    private static func checkConflicts(in document: Document, for path: [String], key: String) throws {
        for header in document.headers {
            if header.path.starts(with: path) || (header.isArray && path.starts(with: header.path)) {
                throw UnsupportedDocument(errorDescription: "\"\(key)\" conflicts with the table [\(header.path.joined(separator: "."))]")
            }
        }
        for keyValue in document.keyValues where keyValue.fullPath != path {
            if path.starts(with: keyValue.fullPath) || keyValue.fullPath.starts(with: path) {
                throw UnsupportedDocument(errorDescription: "\"\(key)\" conflicts with \"\(keyValue.fullPath.joined(separator: "."))\"")
            }
        }
    }

    private static func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func bareOrQuoted(_ key: String) -> String {
        key.allSatisfy(isBareKeyCharacter) ? key : quoted(key)
    }

    fileprivate static func isBareKeyCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber || character == "_" || character == "-")
    }
}

/// The table headers and key/value lines of a TOML document, found line by line. Lines inside multi-line strings and
/// multi-line arrays belong to the value they continue, so their contents are never taken for headers or keys.
private struct Document {
    struct Header {
        let path: [String]
        let isArray: Bool
        let line: Int
        /// The line of the next header, or the line count: the table's lines are before it.
        var sectionEnd: Int
    }

    struct KeyValue {
        let table: [String]
        let fullPath: [String]
        let indentation: String
        /// The line up to and including `=`, as written.
        let keyAndEquals: String
        let firstLine: Int
        var lastLine: Int
        /// The comment after the value, starting with `#`.
        var comment: String?
    }

    private(set) var headers: [Header] = []
    private(set) var keyValues: [KeyValue] = []

    init(lines: [String]) {
        var scanner = ValueScanner()
        var table: [String] = []
        var continuedValue: Int?

        for (index, line) in lines.enumerated() {
            let characters = Array(line)
            if scanner.isInsideValue {
                let comment = scanner.scan(characters, from: 0)
                if let continuedValue {
                    keyValues[continuedValue].lastLine = index
                    keyValues[continuedValue].comment = comment.map { String(characters[$0...]) }
                }
                if !scanner.isInsideValue { continuedValue = nil }
                continue
            }
            if let (path, isArray) = Self.header(in: characters) {
                if let previous = headers.indices.last { headers[previous].sectionEnd = index }
                headers.append(Header(path: path, isArray: isArray, line: index, sectionEnd: lines.count))
                table = path
                continue
            }
            if let (key, valueStart) = Self.keyAndValueStart(in: characters) {
                let comment = scanner.scan(characters, from: valueStart)
                let indentation = String(characters.prefix { $0 == " " || $0 == "\t" })
                keyValues.append(
                    KeyValue(
                        table: table, fullPath: table + key, indentation: indentation,
                        keyAndEquals: String(characters[..<valueStart]), firstLine: index, lastLine: index,
                        comment: comment.map { String(characters[$0...]) }))
                continuedValue = scanner.isInsideValue ? keyValues.count - 1 : nil
                continue
            }
            _ = scanner.scan(characters, from: 0)
        }
    }

    /// `[a.b]` or `[[a.b]]`, with optional spaces and a trailing comment.
    private static func header(in characters: [Character]) -> (path: [String], isArray: Bool)? {
        var index = skippingSpaces(characters, from: 0)
        guard index < characters.count, characters[index] == "[" else { return nil }
        let isArray = index + 1 < characters.count && characters[index + 1] == "["
        index += isArray ? 2 : 1
        guard let path = dottedKey(in: characters, from: &index) else { return nil }
        for _ in 0..<(isArray ? 2 : 1) {
            guard index < characters.count, characters[index] == "]" else { return nil }
            index += 1
        }
        index = skippingSpaces(characters, from: index)
        guard index == characters.count || characters[index] == "#" else { return nil }
        return (path, isArray)
    }

    /// `a.b = ...`: the key's parts and the index after `=`.
    private static func keyAndValueStart(in characters: [Character]) -> (key: [String], valueStart: Int)? {
        var index = skippingSpaces(characters, from: 0)
        guard let key = dottedKey(in: characters, from: &index),
            index < characters.count, characters[index] == "="
        else { return nil }
        return (key, index + 1)
    }

    /// Reads a dotted key of bare and quoted parts, and the spaces after it.
    private static func dottedKey(in characters: [Character], from index: inout Int) -> [String]? {
        var parts: [String] = []
        while true {
            index = skippingSpaces(characters, from: index)
            guard index < characters.count else { return nil }
            var part = ""
            switch characters[index] {
            case "\"", "'":
                let quote = characters[index]
                index += 1
                while index < characters.count, characters[index] != quote {
                    if quote == "\"", characters[index] == "\\", index + 1 < characters.count {
                        index += 1
                    }
                    part.append(characters[index])
                    index += 1
                }
                guard index < characters.count else { return nil }
                index += 1
            default:
                while index < characters.count, TOMLKeyUpdater.isBareKeyCharacter(characters[index]) {
                    part.append(characters[index])
                    index += 1
                }
                guard !part.isEmpty else { return nil }
            }
            parts.append(part)
            index = skippingSpaces(characters, from: index)
            guard index < characters.count, characters[index] == "." else { return parts }
            index += 1
        }
    }

    private static func skippingSpaces(_ characters: [Character], from index: Int) -> Int {
        var index = index
        while index < characters.count, characters[index] == " " || characters[index] == "\t" || characters[index] == "\r" {
            index += 1
        }
        return index
    }
}

/// Follows values across lines: open arrays and inline tables, and multi-line strings.
private struct ValueScanner {
    private var depth = 0
    private var multilineDelimiter: Character?

    var isInsideValue: Bool { depth > 0 || multilineDelimiter != nil }

    /// Scans the rest of a line and returns the index of its comment, if any.
    mutating func scan(_ characters: [Character], from start: Int) -> Int? {
        var index = start
        while index < characters.count {
            let character = characters[index]
            if let delimiter = multilineDelimiter {
                if isTriple(delimiter, in: characters, at: index) {
                    multilineDelimiter = nil
                    index += 3
                } else {
                    index += delimiter == "\"" && character == "\\" ? 2 : 1
                }
                continue
            }
            switch character {
            case "#":
                return index
            case "\"", "'":
                if isTriple(character, in: characters, at: index) {
                    multilineDelimiter = character
                    index += 3
                    continue
                }
                index += 1
                while index < characters.count, characters[index] != character {
                    index += character == "\"" && characters[index] == "\\" ? 2 : 1
                }
            case "[", "{":
                depth += 1
            case "]", "}":
                depth -= 1
            default:
                break
            }
            index += 1
        }
        return nil
    }

    private func isTriple(_ quote: Character, in characters: [Character], at index: Int) -> Bool {
        index + 2 < characters.count && characters[index] == quote && characters[index + 1] == quote
            && characters[index + 2] == quote
    }
}
