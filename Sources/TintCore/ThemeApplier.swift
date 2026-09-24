import Foundation

public struct ApplyOptions: Sendable {
    /// Dark or light; nil picks from the image's brightness.
    public var mode: ThemeMode? = .dark

    /// Accent saturation, 0.5–1.5; see `SchemeBuilder.build`.
    public var saturation: Double = 1

    /// Tell apps to reload. Off: only write the files.
    public var reload = true

    public var cacheDirectory = TintPaths.walCache
    public var templatesDirectory: String? = TintPaths.walTemplates

    /// ApolloShell's themes folder; nil to not write a shell theme.
    public var apolloShellThemes: String? = TintPaths.apolloShellThemes

    public init(mode: ThemeMode? = .dark, saturation: Double = 1, reload: Bool = true) {
        self.mode = mode
        self.saturation = saturation
        self.reload = reload
    }

    /// Options given on the command line win; the rest come from the saved settings.
    public static func resolved(mode: String?, saturation: Double?, reload: Bool = true) -> ApplyOptions {
        let saved = TintSettings.load()
        return ApplyOptions(
            mode: mode.map(TintSettings.parseMode) ?? saved.mode,
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
        let mode = options.mode ?? (palette.isDark ? .dark : .light)
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

        let context = ReloadContext(scheme: scheme, wallpaper: wallpaper, cacheDirectory: options.cacheDirectory)
        let reloads = options.reload ? (reloaders ?? Reloaders.all()).map { $0.reload(context) } : []

        return ApplyResult(palette: palette, scheme: scheme, written: written, warnings: warnings, reloads: reloads)
    }

    /// The image the current theme was made from (pywal's `wal` file), or nil.
    public static func lastApplied(cacheDirectory: String = TintPaths.walCache) -> String? {
        (try? String(contentsOfFile: cacheDirectory + "/wal", encoding: .utf8))?.trimmingWhitespace()
    }
}
