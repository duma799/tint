import Foundation

/// Quoting for the file formats tint writes. Wallpaper paths can contain
/// anything, so none of them may end a string early.
enum Escaping {
    /// A JSON string literal, quotes included.
    static func json(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case let s where s.value < 0x20:
                let hex = String(s.value, radix: 16)
                out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }

    /// The inside of a single-quoted POSIX shell string.
    static func shellSingleQuoted(_ value: String) -> String {
        value.replacingAll("'", with: "'\\''")
    }

    /// The inside of a double-quoted Vimscript string. Backslash first, so the
    /// escapes added after it aren't doubled; line breaks as \n / \r so a
    /// strange filename can't end the string and start a new command.
    static func vim(_ value: String) -> String {
        value.replacingAll("\\", with: "\\\\").replacingAll("\"", with: "\\\"")
            .replacingAll("\n", with: "\\n").replacingAll("\r", with: "\\r")
    }

    /// The inside of a double-quoted CSS string: backslash first, then quotes;
    /// line breaks as CSS hex escapes (a raw newline is invalid there).
    static func css(_ value: String) -> String {
        value.replacingAll("\\", with: "\\\\").replacingAll("\"", with: "\\\"")
            .replacingAll("\n", with: "\\A ").replacingAll("\r", with: "\\D ")
    }
}

extension String {
    func replacingAll(_ target: String, with replacement: String) -> String {
        replacingOccurrences(of: target, with: replacement)
    }
}
