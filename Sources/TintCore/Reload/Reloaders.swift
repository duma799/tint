import Foundation

public struct ReloadContext: Sendable {
    public var scheme: Scheme
    public var wallpaper: String
    public var cacheDirectory: String
}

/// What happened to one app. `skipped` means "not installed / not running" — not an error.
public struct ReloadResult: Sendable {
    public var name: String
    public var ok: Bool
    public var skipped: Bool
    public var detail: String

    static func done(_ name: String, _ detail: String) -> ReloadResult { .init(name: name, ok: true, skipped: false, detail: detail) }
    static func skip(_ name: String, _ detail: String) -> ReloadResult { .init(name: name, ok: true, skipped: true, detail: detail) }
    static func fail(_ name: String, _ detail: String) -> ReloadResult { .init(name: name, ok: false, skipped: false, detail: detail) }
}

/// Tells one app to pick up the new colours.
public protocol Reloader: Sendable {
    var name: String { get }
    func reload(_ context: ReloadContext) -> ReloadResult
}

public enum Reloaders {
    /// The reload steps, in order. The user's hook goes last, so it can build
    /// on (or undo) anything the built-in steps did.
    public static func all() -> [any Reloader] {
        [SketchyBarReloader(), BordersReloader(), GhosttyReloader(), HookReloader()]
    }

    /// Runs a command and turns its outcome into a result.
    static func command(_ name: String, _ program: String, _ arguments: [String]) -> ReloadResult {
        do {
            let result = try ProcessRunner.run(program, arguments)
            return result.succeeded ? .done(name, "reloaded") : .fail(name, "\(program) exited \(result.exitCode): \(result.stderr)")
        } catch {
            return .fail(name, "\(error)")
        }
    }

    /// Runs a script without capturing output (it may start background processes).
    static func script(_ name: String, _ path: String, timeout: TimeInterval, environment: [String: String] = [:], ran: String) -> ReloadResult {
        do {
            switch try ProcessRunner.runDetached(path, timeout: timeout, environment: environment) {
            case 0: return .done(name, ran)
            case nil: return .fail(name, "\(path) still running after \(Int(timeout)) s; left it running")
            case let code?: return .fail(name, "\(path) exited \(code)")
            }
        } catch {
            return .fail(name, "couldn't run \(path): \(error.localizedDescription) (is it executable?)")
        }
    }
}

/// SketchyBar re-runs its `sketchybarrc` on `--reload`, so a bar config that
/// reads `~/.cache/wal` picks up the new colours.
public struct SketchyBarReloader: Reloader {
    public let name = "SketchyBar"

    public init() {}

    public func reload(_ context: ReloadContext) -> ReloadResult {
        guard ProcessRunner.isRunning("sketchybar") else { return .skip(name, "not running") }
        return Reloaders.command(name, "sketchybar", ["--reload"])
    }
}

/// JankyBorders. Calling `borders` with options while it runs updates the
/// running instance, so there's no restart. If there's a
/// `~/.config/borders/bordersrc` it is run — it usually reads `colors.sh` and
/// passes the colours on, keeping your own style; otherwise the active border
/// gets blue (color4) and the inactive one color8.
public struct BordersReloader: Reloader {
    public let name = "JankyBorders"
    let bordersrc: String

    public static var defaultBordersrc: String { TintPaths.home + "/.config/borders/bordersrc" }

    public init(bordersrc: String = BordersReloader.defaultBordersrc) { self.bordersrc = bordersrc }

    public func reload(_ context: ReloadContext) -> ReloadResult {
        guard ProcessRunner.isRunning("borders") else { return .skip(name, "not running") }
        if TintPaths.exists(bordersrc) {
            return Reloaders.script(name, bordersrc, timeout: 10, ran: "reloaded (ran bordersrc)")
        }
        return Reloaders.command(name, "borders", [
            "active_color=0xff\(context.scheme[4].strip)",
            "inactive_color=0xff\(context.scheme[8].strip)",
        ])
    }
}

/// Ghostty 1.2+ reloads its config on SIGUSR2. That only changes colours if
/// the config includes tint's theme file, so it checks for that first:
/// `config-file = ~/.cache/wal/colors-ghostty`.
public struct GhosttyReloader: Reloader {
    public static let themeFile = "colors-ghostty"
    public let name = "Ghostty"
    let configFiles: [String]

    public static var defaultConfigFiles: [String] {
        let env = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
        let xdg = (env?.isEmpty == false ? env! : TintPaths.home + "/.config") + "/ghostty"
        let support = TintPaths.home + "/Library/Application Support/com.mitchellh.ghostty"
        return [xdg + "/config", xdg + "/config.ghostty", support + "/config", support + "/config.ghostty"]
    }

    public init(configFiles: [String] = GhosttyReloader.defaultConfigFiles) { self.configFiles = configFiles }

    /// True if some Ghostty config mentions tint's theme file.
    public func usesTintTheme() -> Bool {
        configFiles.contains { (try? String(contentsOfFile: $0, encoding: .utf8))?.contains(GhosttyReloader.themeFile) == true }
    }

    public func reload(_ context: ReloadContext) -> ReloadResult {
        guard ProcessRunner.isRunning("ghostty") else { return .skip(name, "not running") }
        guard usesTintTheme() else {
            return .skip(name, "add `config-file = ~/.cache/wal/\(GhosttyReloader.themeFile)` to your Ghostty config to theme it")
        }
        return Reloaders.command(name, "pkill", ["-USR2", "-x", "ghostty"])
    }
}

/// Runs `~/.config/tint/hooks/post-apply` if it exists and is executable —
/// the place for setup-specific steps (editor themes…). It gets
/// TINT_WALLPAPER, TINT_MODE and TINT_CACHE.
public struct HookReloader: Reloader {
    public let name = "post-apply hook"
    let hooksDirectory: String

    public init(hooksDirectory: String = TintPaths.hooks) { self.hooksDirectory = hooksDirectory }

    public func reload(_ context: ReloadContext) -> ReloadResult {
        let hook = hooksDirectory + "/post-apply"
        guard TintPaths.exists(hook) else { return .skip(name, "no \(hook)") }
        guard FileManager.default.isExecutableFile(atPath: hook) else {
            return .fail(name, "\(hook) is not executable (chmod +x it)")
        }
        return Reloaders.script(name, hook, timeout: 30, environment: [
            "TINT_WALLPAPER": context.wallpaper,
            "TINT_MODE": context.scheme.mode.rawValue,
            "TINT_CACHE": context.cacheDirectory,
        ], ran: "ran")
    }
}
