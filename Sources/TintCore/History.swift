import Foundation

/// One theme tint applied: enough to bring it back exactly.
public struct HistoryEntry: Codable, Equatable, Sendable {
    public var wallpaper: String
    /// The mode the scheme was made in (already resolved: dark or light).
    public var mode: ThemeMode
    public var saturation: Double
    public var date: Date
    /// The 16 colours, for showing the entry without recomputing it.
    public var colors: [String]

    public init(wallpaper: String, mode: ThemeMode, saturation: Double, date: Date = Date(), colors: [String]) {
        self.wallpaper = wallpaper
        self.mode = mode
        self.saturation = saturation
        self.date = date
        self.colors = colors
    }

    /// Same theme (the date aside).
    func sameTheme(as other: HistoryEntry) -> Bool {
        wallpaper == other.wallpaper && mode == other.mode && abs(saturation - other.saturation) < 0.001
    }
}

/// The last themes applied, newest first, in `~/.config/tint/history.json`.
/// `tint back` and the menu bar's "Recent" read it.
public enum ThemeHistory {
    public static var defaultPath: String { TintPaths.config + "/history.json" }
    public static let limit = 30

    public static func load(from path: String = defaultPath) -> [HistoryEntry] {
        guard let data = FileManager.default.contents(atPath: path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
    }

    public static func save(_ entries: [HistoryEntry], to path: String = defaultPath) throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try PywalWriter.atomicWrite(String(decoding: try encoder.encode(entries), as: UTF8.self) + "\n", to: path)
    }

    /// Adds `entry` as the newest. Applying the same theme again only moves it to the top.
    public static func record(_ entry: HistoryEntry, to path: String = defaultPath) throws {
        var entries = load(from: path).filter { !$0.sameTheme(as: entry) }
        entries.insert(entry, at: 0)
        try save(Array(entries.prefix(limit)), to: path)
    }
}

/// Pausing: the watcher keeps running but leaves wallpaper changes alone
/// until resumed. A flag file, so the CLI, the app and the service agree.
public enum Pause {
    public static var flagPath: String { TintPaths.config + "/paused" }

    public static var isPaused: Bool { TintPaths.exists(flagPath) }

    public static func set(_ paused: Bool) throws {
        if paused {
            try FileManager.default.createDirectory(atPath: TintPaths.config, withIntermediateDirectories: true)
            try PywalWriter.atomicWrite("paused by tint — `tint resume` or the menu bar undoes it\n", to: flagPath)
        } else if isPaused {
            try FileManager.default.removeItem(atPath: flagPath)
        }
    }
}
