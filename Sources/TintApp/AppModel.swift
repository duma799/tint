#if os(macOS)
import AppKit
import Observation
import ServiceManagement
import TintCore

extension ModePreference: Identifiable {
    public var id: Self { self }

    var label: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        case .auto: "Image"
        case .system: "System"
        }
    }

    var help: String {
        switch self {
        case .dark: "Always a dark scheme"
        case .light: "Always a light scheme"
        case .auto: "Dark or light, from the image's brightness"
        case .system: "Follow macOS's appearance, and switch when it does"
        }
    }
}

/// Everything the window and the menu bar show: the chosen image, its
/// palette, the knobs, and what happened on the last apply.
@MainActor
@Observable
final class AppModel {
    var imagePath: String?
    var image: NSImage?
    var palette: Palette?
    var mode: ModePreference
    var saturation: Double
    var setAsWallpaper = false
    /// The "Open image…" file picker is showing.
    var importing = false
    var status = ""
    var busy = false
    var currentWallpaper: String?
    var service: ServiceStatus?

    /// macOS's appearance now, for the "System" mode; kept current below.
    var systemIsDark = SystemAppearance.isDark()

    /// Whether the app opens at login (as a menu bar item, without its window).
    var openAtLogin = SMAppService.mainApp.status == .enabled

    /// The latest themes, newest first (`tint history`).
    var history: [HistoryEntry] = ThemeHistory.load()

    /// Whether the watcher is ignoring wallpaper changes (`tint pause`).
    var paused = Pause.isPaused

    @ObservationIgnored private var appearanceObserver: (any NSObjectProtocol)?

    init() {
        let saved = TintSettings.load()
        mode = saved.mode
        saturation = saved.saturation
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: SystemAppearance.changedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemIsDark = SystemAppearance.isDark() }
        }
    }

    func refreshHistory() {
        history = ThemeHistory.load()
        paused = Pause.isPaused
    }

    func setPaused(_ on: Bool) {
        do {
            try Pause.set(on)
            status = on ? "Paused: wallpaper changes are left alone." : "Watching wallpaper changes again."
        } catch {
            status = "Couldn't change it: \(error.localizedDescription)"
        }
        paused = Pause.isPaused
    }

    /// Undo the latest theme.
    func back() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            if let (entry, _) = try await Task.detached(operation: { try ThemeApplier.back() }).value {
                status = "Back to \((entry.wallpaper as NSString).lastPathComponent)"
            } else {
                status = "No earlier theme to go back to."
            }
        } catch {
            status = "Couldn't go back: \(error)"
        }
        refreshHistory()
    }

    /// Re-apply a theme from "Recent".
    func restore(_ entry: HistoryEntry) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await Task.detached(operation: { try ThemeApplier.restore(entry, record: true) }).value
            status = "Restored \((entry.wallpaper as NSString).lastPathComponent)"
        } catch {
            status = "Couldn't restore it: \(error)"
        }
        refreshHistory()
    }

    func openLog() {
        NSWorkspace.shared.open(URL(fileURLWithPath: TintPaths.log))
    }

    func setOpenAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            status = on ? "✓ tint opens at login, in the menu bar." : "tint no longer opens at login."
        } catch {
            status = "Couldn't change it: \(error.localizedDescription) — is Tint in Applications?"
        }
        openAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// The scheme for the current image and knobs; nil until an image is loaded.
    var scheme: Scheme? {
        guard let palette else { return nil }
        return try? SchemeBuilder.build(palette, mode: mode.resolve(for: palette) { self.systemIsDark }, saturation: roundedSaturation)
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

        let settings = TintSettings(mode: mode, saturation: roundedSaturation)
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
            refreshHistory()
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
