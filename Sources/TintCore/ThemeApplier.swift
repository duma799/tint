import Foundation

public struct ApplyOptions: Sendable {
    /// Dark, light, from the image (auto) or from macOS (system).
    public var mode: ModePreference = .dark

    /// Accent saturation, 0.5–1.5; see `SchemeBuilder.build`.
    public var saturation: Double = 1

    /// Tell apps to reload. Off: only write the files.
    public var reload = true

    public var cacheDirectory = TintPaths.walCache
    public var templatesDirectory: String? = TintPaths.walTemplates

    /// ApolloShell's themes folder; nil to not write a shell theme.
    public var apolloShellThemes: String? = TintPaths.apolloShellThemes

    /// Where to remember applied themes (`tint back`); nil to not record this one.
    public var history: String? = ThemeHistory.defaultPath

    /// Where to look for editors to theme (Zed, VS Code, Antigravity, Gemini CLI); nil for none.
    public var editors: EditorThemes.Paths? = EditorThemes.Paths()

    public init(mode: ModePreference = .dark, saturation: Double = 1, reload: Bool = true) {
        self.mode = mode
        self.saturation = saturation
        self.reload = reload
    }

    /// Options given on the command line win; the rest come from the saved settings.
    public static func resolved(mode: String?, saturation: Double?, reload: Bool = true) -> ApplyOptions {
        let saved = TintSettings.load()
        return ApplyOptions(
            mode: mode.map { ModePreference(name: $0) } ?? saved.mode,
            saturation: saturation ?? saved.saturation,
            reload: reload)
    }
}

public struct ApplyResult: Sendable {
    public var palette: Palette
    public var scheme: Scheme
    public var written: [String]
    public var warnings: [String]
    public var reloads: [ReloadResult]
}

/// The whole of `tint apply`: image → palette → scheme → files → app reloads.
public enum ThemeApplier {
    public static func apply(image: String, options: ApplyOptions = ApplyOptions(), reloaders: [any Reloader]? = nil) throws -> ApplyResult {
        let wallpaper = URL(fileURLWithPath: image).standardizedFileURL.path
        let palette = try PaletteExtractor.extract(file: wallpaper)
        return try apply(palette: palette, wallpaper: wallpaper, options: options, reloaders: reloaders)
    }

    /// Everything after palette extraction — for callers that already have the palette (the app).
    public static func apply(palette: Palette, wallpaper: String, options: ApplyOptions, reloaders: [any Reloader]? = nil) throws -> ApplyResult {
        let mode = options.mode.resolve(for: palette)
        let scheme = try SchemeBuilder.build(palette, mode: mode, saturation: options.saturation)

        let files = try PywalWriter.write(scheme, wallpaper: wallpaper, to: options.cacheDirectory, templates: options.templatesDirectory)
        var written = files.written
        var warnings = files.warnings
        if let themes = options.apolloShellThemes {
            do {
                if let path = try ApolloShellTheme.write(scheme, wallpaper: wallpaper, themesDirectory: themes) {
                    written.append(path)
                }
            } catch {
                warnings.append("couldn't write the ApolloShell theme: \(error.localizedDescription)")
            }
        }

        if let paths = options.editors {
            let editors = EditorThemes.write(scheme, paths: paths)
            written += editors.written
            warnings += editors.warnings
        }

        if let history = options.history {
            let entry = HistoryEntry(wallpaper: wallpaper, mode: mode, saturation: options.saturation, colors: scheme.colors.map(\.hex))
            do {
                try ThemeHistory.record(entry, to: history)
            } catch {
                warnings.append("couldn't save the theme history: \(error.localizedDescription)")
            }
        }

        let context = ReloadContext(scheme: scheme, wallpaper: wallpaper, cacheDirectory: options.cacheDirectory)
        let reloads = options.reload ? (reloaders ?? Reloaders.all()).map { $0.reload(context) } : []

        return ApplyResult(palette: palette, scheme: scheme, written: written, warnings: warnings, reloads: reloads)
    }

    /// The image the current theme was made from (pywal's `wal` file), or nil.
    public static func lastApplied(cacheDirectory: String = TintPaths.walCache) -> String? {
        (try? String(contentsOfFile: cacheDirectory + "/wal", encoding: .utf8))?.trimmingWhitespace()
    }

    /// Brings back a theme from the history: the same image, mode and
    /// saturation — and the image as the wallpaper again, if it's a file you
    /// chose (not one of macOS's rendered snapshots) and isn't already.
    /// - Parameter record: add it to the history as the newest (a pick from
    ///   "Recent"); `tint back` doesn't, it removes the undone one instead.
    public static func restore(_ entry: HistoryEntry, base: ApplyOptions = ApplyOptions(), record: Bool) throws -> ApplyResult {
        var options = base
        options.mode = entry.mode == .dark ? .dark : .light
        options.saturation = entry.saturation
        if !record { options.history = nil }
        let result = try apply(image: entry.wallpaper, options: options)

        #if os(macOS)
        // After applying, so a running `tint watch` finds it already themed.
        let isSnapshot = entry.wallpaper.contains("com.apple.wallpaper.caches")
        if !isSnapshot, TintPaths.exists(entry.wallpaper), MacWallpaper.current().path != entry.wallpaper {
            try MacWallpaper.set(entry.wallpaper)
        }
        #endif
        return result
    }

    /// Undoes the latest theme: brings back the one before it (`steps` back)
    /// and drops the undone ones from the history.
    public static func back(steps: Int = 1, base: ApplyOptions = ApplyOptions(), historyPath: String = ThemeHistory.defaultPath) throws -> (HistoryEntry, ApplyResult)? {
        let entries = ThemeHistory.load(from: historyPath)
        guard steps >= 1, entries.count > steps else { return nil }
        let target = entries[steps]
        var options = base
        options.history = nil
        let result = try restore(target, base: options, record: false)
        try ThemeHistory.save(Array(entries.dropFirst(steps)), to: historyPath)
        return (target, result)
    }
}
