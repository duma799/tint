import Foundation

public enum CheckStatus: Sendable {
    case ok, info, warning, problem
}

public struct Check: Sendable {
    public var name: String
    public var status: CheckStatus
    public var detail: String
}

/// `tint doctor`: checks everything tint depends on and says what to fix.
public enum Doctor {
    public static func run() -> [Check] {
        var checks: [Check] = []
        #if os(macOS)
        checks.append(Check(name: "macOS", status: .ok, detail: ProcessInfo.processInfo.operatingSystemVersionString))
        let lookup = MacWallpaper.current()
        checks.append(lookup.path.map { Check(name: "wallpaper", status: .ok, detail: $0) }
            ?? Check(name: "wallpaper", status: .problem, detail: lookup.notice ?? "couldn't find the current wallpaper"))
        #else
        checks.append(Check(name: "macOS", status: .problem, detail: "tint runs on macOS only"))
        #endif

        checks.append(themeFiles())
        let settingsNote = TintPaths.exists(TintSettings.defaultPath) ? "" : " (defaults)"
        checks.append(Check(name: "settings", status: .info, detail: "\(TintSettings.load())\(settingsNote)"))
        checks.append(sketchyBar())
        checks.append(borders())
        checks.append(ghostty())
        checks.append(wezterm())
        checks.append(apolloShell())
        checks.append(editors())
        checks.append(templates())
        checks.append(hook())
        #if os(macOS)
        checks.append(service())
        #endif
        if TintPaths.onPath("wal") {
            checks.append(Check(name: "pywal", status: .warning,
                detail: "`wal` is still installed — anything that runs it will overwrite tint's colours. pip3 uninstall pywal once you've switched"))
        }
        return checks
    }

    static func themeFiles() -> Check {
        let json = TintPaths.walCache + "/colors.json"
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: json),
              let date = attributes[.modificationDate] as? Date
        else { return Check(name: "theme", status: .warning, detail: "no theme yet — run `tint apply`") }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return Check(name: "theme", status: .ok, detail: "from \(ThemeApplier.lastApplied() ?? "?"), \(formatter.string(from: date))")
    }

    static func sketchyBar() -> Check {
        guard TintPaths.onPath("sketchybar") else { return Check(name: "SketchyBar", status: .info, detail: "not installed") }
        return ProcessRunner.isRunning("sketchybar")
            ? Check(name: "SketchyBar", status: .ok, detail: "running — reloaded on every apply")
            : Check(name: "SketchyBar", status: .warning, detail: "installed but not running (brew services start sketchybar)")
    }

    static func borders() -> Check {
        guard TintPaths.onPath("borders") else { return Check(name: "JankyBorders", status: .info, detail: "not installed") }
        let how = TintPaths.exists(BordersReloader.defaultBordersrc)
            ? "re-runs ~/.config/borders/bordersrc" : "sets active/inactive colours (no bordersrc)"
        return ProcessRunner.isRunning("borders")
            ? Check(name: "JankyBorders", status: .ok, detail: "running — \(how) on every apply")
            : Check(name: "JankyBorders", status: .warning, detail: "installed but not running (brew services start borders)")
    }

    static func ghostty() -> Check {
        guard TintPaths.isDirectory("/Applications/Ghostty.app") || TintPaths.onPath("ghostty") else {
            return Check(name: "Ghostty", status: .info, detail: "not installed")
        }
        return GhosttyReloader().usesTintTheme()
            ? Check(name: "Ghostty", status: .ok, detail: "uses tint's theme — reloaded on every apply (Ghostty 1.2+)")
            : Check(name: "Ghostty", status: .warning, detail: "add `config-file = ~/.cache/wal/\(GhosttyReloader.themeFile)` to its config")
    }

    static func wezterm() -> Check {
        guard TintPaths.isDirectory("/Applications/WezTerm.app") || TintPaths.onPath("wezterm") else {
            return Check(name: "WezTerm", status: .info, detail: "not installed")
        }
        let configs = [TintPaths.home + "/.wezterm.lua", TintPaths.home + "/.config/wezterm/wezterm.lua"]
        let uses = configs.contains { (try? String(contentsOfFile: $0, encoding: .utf8))?.contains("colors-wezterm.toml") == true }
        return uses
            ? Check(name: "WezTerm", status: .ok, detail: "uses tint's scheme — reloads itself when it changes")
            : Check(name: "WezTerm", status: .warning, detail: "load ~/.cache/wal/colors-wezterm.toml in wezterm.lua (see the README)")
    }

    static func apolloShell() -> Check {
        let themes = TintPaths.apolloShellThemes
        guard TintPaths.isDirectory((themes as NSString).deletingLastPathComponent) else {
            return Check(name: "ApolloShell", status: .info, detail: "not installed")
        }
        return TintPaths.exists(themes + "/" + ApolloShellTheme.fileName)
            ? Check(name: "ApolloShell", status: .ok, detail: "tint.css is written on every apply — pick \"tint\" in Nexus → Themes")
            : Check(name: "ApolloShell", status: .warning, detail: "installed; run `tint apply` to write its tint theme")
    }

    static func editors() -> Check {
        let paths = EditorThemes.Paths()
        let found = [
            ("Zed", TintPaths.isDirectory(paths.zed)),
            ("VS Code", TintPaths.exists(paths.vscode + "/settings.json")),
            ("Antigravity", TintPaths.exists(paths.antigravity + "/settings.json")),
            ("Gemini CLI", TintPaths.isDirectory(paths.gemini)),
        ].filter(\.1).map(\.0)
        return found.isEmpty
            ? Check(name: "editors", status: .info, detail: "none found (Zed, VS Code, Antigravity, Gemini CLI)")
            : Check(name: "editors", status: .ok, detail: "themed on every apply: \(found.joined(separator: ", ")) — \"Tint\" theme in Zed and VS Code")
    }

    static func templates() -> Check {
        let dir = TintPaths.walTemplates
        let count = (try? FileManager.default.contentsOfDirectory(atPath: dir))?.filter { !$0.hasPrefix(".") }.count ?? 0
        return Check(name: "templates", status: .info, detail: count == 0 ? "none in \(dir)" : "\(count) in \(dir)")
    }

    static func hook() -> Check {
        let hook = TintPaths.hooks + "/post-apply"
        guard TintPaths.exists(hook) else { return Check(name: "hook", status: .info, detail: "none (\(hook))") }
        return FileManager.default.isExecutableFile(atPath: hook)
            ? Check(name: "hook", status: .ok, detail: hook)
            : Check(name: "hook", status: .problem, detail: "\(hook) is not executable — chmod +x it")
    }

    static func service() -> Check {
        let status = LaunchAgent.status()
        guard status.installed else {
            return Check(name: "service", status: .info, detail: "not installed — `tint service install` themes on every wallpaper change, from login")
        }
        if let program = status.programArguments.first, !TintPaths.exists(program) {
            return Check(name: "service", status: .problem, detail: "points at \(program), which is gone — run `tint service install` again")
        }
        return status.running
            ? Check(name: "service", status: .ok, detail: "running (pid \(status.pid!)), log: \(TintPaths.log)")
            : Check(name: "service", status: .problem, detail: "installed but not running — see \(TintPaths.log), then `tint service restart`")
    }
}
