import Foundation
import TintCore

/// Terminal output helpers: colour swatches, timestamps, errors.
enum Terminal {
    /// 24-bit colour escapes, unless output is piped or the user opted out (https://no-color.org).
    static let useColor = isatty(STDOUT_FILENO) != 0 && (ProcessInfo.processInfo.environment["NO_COLOR"] ?? "").isEmpty

    /// A block of the given colour, `width` cells wide.
    static func block(_ c: Rgb, _ width: Int = 6) -> String {
        useColor ? "\u{1B}[48;2;\(c.r);\(c.g);\(c.b)m\(String(repeating: " ", count: width))\u{1B}[0m" : ""
    }

    static func strip(_ scheme: Scheme, width: Int = 2) -> String { scheme.colors.map { block($0, width) }.joined() }
    static func strip(_ palette: Palette, width: Int = 3) -> String { palette.swatches.map { block($0.color, width) }.joined() }

    static func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        say("[\(formatter.string(from: Date()))] \(message)")
    }

    static func error(_ message: String) {
        FileHandle.standardError.write(Data("tint: \(message)\n".utf8))
    }

    static func warn(_ message: String) {
        FileHandle.standardError.write(Data("  ! \(message)\n".utf8))
    }
}

/// Prints a line, unbuffered — so the service's log file is always current.
func say(_ line: String = "") {
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

/// Exit quietly with a status (the message was already printed).
struct Failed: Error {}
