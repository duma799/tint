import Foundation

/// Where tint reads and writes. The same paths pywal uses, so existing configs keep working.
public enum TintPaths {
    public static var home: String {
        ProcessInfo.processInfo.environment["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
    }

    /// pywal-compatible output, `~/.cache/wal` — what SketchyBar, JankyBorders and Neovim read.
    public static var walCache: String { home + "/.cache/wal" }

    /// pywal user templates, `~/.config/wal/templates`.
    public static var walTemplates: String { home + "/.config/wal/templates" }

    /// tint's own config folder, `~/.config/tint`.
    public static var config: String { home + "/.config/tint" }

    /// tint's hooks, `~/.config/tint/hooks`.
    public static var hooks: String { config + "/hooks" }

    /// Where the login service writes its output, `~/Library/Logs/tint.log`.
    public static var log: String { home + "/Library/Logs/tint.log" }

    /// ApolloShell's theme folder; tint writes `tint.css` there when it exists.
    public static var apolloShellThemes: String { home + "/Library/Application Support/ApolloShell/themes" }

    /// Full path of `command` on the PATH, or nil.
    public static func findOnPath(_ command: String, path: String? = nil) -> String? {
        let dirs = (path ?? ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
        return dirs.map { "\($0)/\(command)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public static func onPath(_ command: String) -> Bool { findOnPath(command) != nil }

    /// `path` with symlinks resolved, so two routes to one file compare equal.
    public static func realPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    public static func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

    public static func isDirectory(_ path: String) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
    }
}
