import Foundation

/// Edits settings files written in "JSON with comments" (VS Code's
/// settings.json allows `//` and `/* */` comments and trailing commas) by
/// replacing or adding a single top-level key in the text, so everything
/// else — comments, order, formatting — stays exactly as the user wrote it.
struct JSONCEditor {
    private(set) var text: String

    enum Failure: Error, CustomStringConvertible {
        case notAnObject
        case brokenResult

        var description: String {
            switch self {
            case .notAnObject: "isn't a JSON object"
            case .brokenResult: "couldn't be edited safely, so tint left it alone"
            }
        }
    }

    init(_ text: String) { self.text = text }

    /// The file's value, read by skipping comments and trailing commas.
    static func parse(_ text: String) -> Any? {
        let plain = strip(text)
        return try? JSONSerialization.jsonObject(with: Data(plain.utf8))
    }

    /// Sets top-level `key` to `value` (any JSON-serialisable value).
    mutating func set(_ key: String, _ value: Any) throws {
        let chars = Array(text)
        guard let open = firstSignificant(chars, from: 0), chars[open] == "{" else { throw Failure.notAnObject }
        let indent = detectIndent(chars)
        let rendered = try render(value, indent: indent)

        let edited: String
        if let range = valueRange(ofTopLevelKey: key, in: chars) {
            edited = String(chars[..<range.lowerBound]) + rendered + String(chars[range.upperBound...])
        } else {
            guard let close = topLevelClose(chars) else { throw Failure.notAnObject }
            let last = lastSignificant(chars, before: close)
            let entry = "\n" + indent + Escaping.json(key) + ": " + rendered
            if let last, chars[last] != "{" {
                let comma = chars[last] == "," ? "" : ","
                edited = String(chars[...last]) + comma + entry + String(chars[(last + 1)...])
            } else {
                edited = String(chars[...open]) + entry + "\n" + String(chars[(open + 1)...])
            }
        }

        // Never write something that no longer reads back as the same kind of file.
        guard JSONCEditor.parse(edited) is [String: Any] else { throw Failure.brokenResult }
        text = edited
    }

    // MARK: Scanning

    /// The text with comments removed and trailing commas dropped (strings untouched).
    static func strip(_ text: String) -> String {
        var out = ""
        let chars = Array(text)
        var i = 0
        var inString = false
        while i < chars.count {
            let c = chars[i]
            if inString {
                out.append(c)
                if c == "\\", i + 1 < chars.count {
                    out.append(chars[i + 1])
                    i += 2
                    continue
                }
                if c == "\"" { inString = false }
                i += 1
                continue
            }
            if c == "\"" {
                inString = true
                out.append(c)
                i += 1
            } else if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                while i < chars.count, chars[i] != "\n" { i += 1 }
            } else if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                i += 2
                while i + 1 < chars.count, !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                i += 2
            } else if c == "," {
                // Drop a comma that only has whitespace/comments before a closing bracket.
                var j = i + 1
                var sawClose = false
                while j < chars.count {
                    if chars[j].isWhitespace { j += 1; continue }
                    if chars[j] == "/", j + 1 < chars.count, chars[j + 1] == "/" {
                        while j < chars.count, chars[j] != "\n" { j += 1 }
                        continue
                    }
                    if chars[j] == "/", j + 1 < chars.count, chars[j + 1] == "*" {
                        j += 2
                        while j + 1 < chars.count, !(chars[j] == "*" && chars[j + 1] == "/") { j += 1 }
                        j += 2
                        continue
                    }
                    sawClose = chars[j] == "}" || chars[j] == "]"
                    break
                }
                if !sawClose { out.append(c) }
                i += 1
            } else {
                out.append(c)
                i += 1
            }
        }
        return out
    }

    /// Skips whitespace and comments from `i`; the index of the next real character.
    private func firstSignificant(_ chars: [Character], from start: Int) -> Int? {
        var i = start
        while i < chars.count {
            if chars[i].isWhitespace {
                i += 1
            } else if chars[i] == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                while i < chars.count, chars[i] != "\n" { i += 1 }
            } else if chars[i] == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                i += 2
                while i + 1 < chars.count, !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                i += 2
            } else {
                return i
            }
        }
        return nil
    }

    /// Walks the text calling `visit(index, depth)` for every character outside
    /// strings and comments; strings are reported once, at their opening quote.
    private func walk(_ chars: [Character], _ visit: (Int, Int, Bool) -> Bool) {
        var i = 0, depth = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                if !visit(i, depth, true) { return }
                i += 1
                while i < chars.count, chars[i] != "\"" { i += chars[i] == "\\" ? 2 : 1 }
                i += 1
                continue
            }
            if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                while i < chars.count, chars[i] != "\n" { i += 1 }
                continue
            }
            if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                i += 2
                while i + 1 < chars.count, !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                i += 2
                continue
            }
            if c == "}" || c == "]" { depth -= 1 }
            if !visit(i, depth, false) { return }
            if c == "{" || c == "[" { depth += 1 }
            i += 1
        }
    }

    private func stringEnd(_ chars: [Character], _ start: Int) -> Int {
        var i = start + 1
        while i < chars.count, chars[i] != "\"" { i += chars[i] == "\\" ? 2 : 1 }
        return i + 1
    }

    /// The span of the value of a key directly inside the top-level object.
    private func valueRange(ofTopLevelKey key: String, in chars: [Character]) -> Range<Int>? {
        var found: Range<Int>?
        walk(chars) { i, depth, isString in
            guard isString, depth == 1 else { return true }
            let end = stringEnd(chars, i)
            guard let name = try? JSONSerialization.jsonObject(with: Data(String(chars[i..<end]).utf8), options: .fragmentsAllowed) as? String,
                  name == key,
                  let colon = firstSignificant(chars, from: end), chars[colon] == ":",
                  let start = firstSignificant(chars, from: colon + 1)
            else { return true }
            found = start..<valueEnd(chars, start)
            return false
        }
        return found
    }

    /// Where a value starting at `start` ends.
    private func valueEnd(_ chars: [Character], _ start: Int) -> Int {
        switch chars[start] {
        case "\"":
            return stringEnd(chars, start)
        case "{", "[":
            var end = chars.count
            var base: Int?
            walk(chars) { i, depth, isString in
                guard i >= start, !isString else { return true }
                if base == nil { base = depth }
                if i > start, depth == base, chars[i] == "}" || chars[i] == "]" {
                    end = i + 1
                    return false
                }
                return true
            }
            return end
        default:
            var i = start
            while i < chars.count, !",}\n".contains(chars[i]), !(chars[i] == "/" && i + 1 < chars.count && "/*".contains(chars[i + 1])) {
                i += 1
            }
            while i > start, chars[i - 1].isWhitespace { i -= 1 }
            return i
        }
    }

    /// The top-level object's closing brace.
    private func topLevelClose(_ chars: [Character]) -> Int? {
        var close: Int?
        walk(chars) { i, depth, isString in
            if !isString, depth == 0, chars[i] == "}" { close = i }
            return true
        }
        return close
    }

    /// The last real (non-space, non-comment) character before `index`.
    private func lastSignificant(_ chars: [Character], before index: Int) -> Int? {
        var last: Int?
        walk(chars) { i, _, isString in
            guard i < index else { return false }
            last = isString ? stringEnd(chars, i) - 1 : (chars[i].isWhitespace ? last : i)
            return true
        }
        return last
    }

    /// The file's own indent unit (the leading whitespace of its first indented key), else 4 spaces.
    private func detectIndent(_ chars: [Character]) -> String {
        for line in String(chars).split(separator: "\n") {
            let leading = line.prefix { $0 == " " || $0 == "\t" }
            if !leading.isEmpty, line.dropFirst(leading.count).first == "\"" { return String(leading) }
        }
        return "    "
    }

    /// `value` as indented JSON, fitting in at the top level of the file.
    private func render(_ value: Any, indent: String) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
        return lines.enumerated().map { n, line in
            // JSONSerialization indents by two spaces; use the file's own unit instead.
            let spaces = line.prefix { $0 == " " }.count
            let body = line.dropFirst(spaces)
            return n == 0 ? String(body) : indent + String(repeating: indent, count: spaces / 2) + body
        }.joined(separator: "\n")
    }
}
