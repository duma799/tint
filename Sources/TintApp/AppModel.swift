#if os(macOS)
import AppKit
import Observation
import TintCore

enum ModeChoice: String, CaseIterable, Identifiable {
    case dark, light, auto

    var id: Self { self }
    var label: String { rawValue.capitalized }
    var themeMode: ThemeMode? { self == .auto ? nil : ThemeMode(rawValue: rawValue) }

    init(_ mode: ThemeMode?) { self = mode.flatMap { ModeChoice(rawValue: $0.rawValue) } ?? .auto }
}

/// Everything the window and the menu bar show: the chosen image, its
/// palette, the knobs, and what happened on the last apply.
@MainActor
@Observable
final class AppModel {
    var imagePath: String?
    var image: NSImage?
    var palette: Palette?
    var mode: ModeChoice
    var saturation: Double
    var setAsWallpaper = false
    var status = ""
    var busy = false
    var currentWallpaper: String?
    var service: ServiceStatus?

    init() {
        let saved = TintSettings.load()
        mode = ModeChoice(saved.mode)
        saturation = saved.saturation
    }

    /// The scheme for the current image and knobs; nil until an image is loaded.
    var scheme: Scheme? {
        guard let palette else { return nil }
        let resolved = mode.themeMode ?? (palette.isDark ? .dark : .light)
        return try? SchemeBuilder.build(palette, mode: resolved, saturation: roundedSaturation)
    }

    var roundedSaturation: Double { (saturation * 20).rounded() / 20 }

    var canSetWallpaper: Bool { imagePath != nil && imagePath != currentWallpaper }

    /// The installed `tint` command, which the login service runs.
    var cli: String? { ["/opt/homebrew/bin/tint", "/usr/local/bin/tint"].first { FileManager.default.isExecutableFile(atPath: $0) } }

    func start() async {
        guard !started else { return }
        started = true
        await refreshService()
        // TINT_APP_IMAGE opens on a given image instead (screenshots, trying things out).
        if let image = ProcessInfo.processInfo.environment["TINT_APP_IMAGE"] {
            await load(image)
        } else {
            await loadCurrentWallpaper()
        }
    }

    private var started = false

    func loadCurrentWallpaper() async {
        let lookup = await Task.detached { MacWallpaper.current() }.value
        guard let path = lookup.path else {
            status = lookup.notice ?? "Couldn't find the current wallpaper — open an image instead."
            return
        }
        currentWallpaper = path
        await load(path)
    }

    /// Reads the image's palette off the main thread, then shows it.
    func load(_ path: String) async {
        status = "Reading \((path as NSString).lastPathComponent)…"
        do {
            let palette = try await Task.detached { try PaletteExtractor.extract(file: path) }.value
            imagePath = path
            image = NSImage(contentsOfFile: path)
            self.palette = palette
            setAsWallpaper = false
            status = ""
        } catch {
            // Forget the previous image too: Apply must never use a different
            // image from the one just asked for.
            imagePath = nil
            image = nil
            palette = nil
            status = "Couldn't read it: \(error)"
        }
    }

    func apply() async {
        guard let path = imagePath, let palette, !busy else { return }
        busy = true
        defer { busy = false }
        status = "Applying…"

        let settings = TintSettings(mode: mode.themeMode, saturation: roundedSaturation)
        let setWallpaper = setAsWallpaper && canSetWallpaper
        do {
            let result = try await Task.detached {
                try settings.save()
                return try ThemeApplier.apply(
                    palette: palette, wallpaper: path,
                    options: ApplyOptions(mode: settings.mode, saturation: settings.saturation))
            }.value

            // After applying, so a running `tint watch` finds this image
            // already themed and leaves it alone.
            if setWallpaper {
                try MacWallpaper.set(path)
                currentWallpaper = path
                setAsWallpaper = false
            }
            status = describe(result, setWallpaper: setWallpaper)
        } catch {
            status = "Couldn't apply: \(error)"
        }
    }

    /// Re-themes from whatever is on the desktop now (the menu bar's button).
    func applyCurrentWallpaper() async {
        await loadCurrentWallpaper()
        if imagePath == currentWallpaper { await apply() }
    }

    func refreshService() async {
        service = await Task.detached { LaunchAgent.status() }.value
    }

    func installService() async {
        guard let cli else { return }
        do {
            try await Task.detached { try LaunchAgent.install(programArguments: [cli, "watch"]) }.value
            status = "✓ tint now re-themes on every wallpaper change, from login."
        } catch {
            status = "Couldn't start the service: \(error)"
        }
        await refreshService()
    }

    func copy(_ color: Rgb, index: Int) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(color.hex, forType: .string)
        status = "Copied color\(index) \(color.hex)"
    }

    private func describe(_ result: ApplyResult, setWallpaper: Bool) -> String {
        var lines = ["✓ wrote \(result.written.count) files"]
        if setWallpaper { lines.append("✓ set as the wallpaper") }
        for r in result.reloads {
            lines.append("\(r.skipped ? "·" : r.ok ? "✓" : "✗") \(r.name): \(r.detail)")
        }
        lines += result.warnings.map { "! \($0)" }
        return lines.joined(separator: "\n")
    }
}
#endif
