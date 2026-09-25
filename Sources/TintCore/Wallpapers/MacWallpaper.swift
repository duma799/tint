import Foundation

#if os(macOS)
import AppKit
#endif

/// The current macOS wallpaper, and setting it.
///
/// The image comes from, in order: the file macOS reports for the main
/// screen (photos and pictures); the file URL inside the wallpaper store
/// (`Index.plist`); and, for wallpapers with no file at all (the macOS 26
/// extension wallpapers like Neptune), the snapshot macOS rendered of it.
public enum MacWallpaper {
    static var storeDirectory: String { TintPaths.home + "/Library/Application Support/com.apple.wallpaper" }

    /// Where the wallpaper service keeps rendered snapshots of each wallpaper,
    /// one folder per provider (`extension-<provider id>`).
    static var snapshotCache: String {
        TintPaths.home + "/Library/Containers/com.apple.wallpaper.agent/Data/Library/Caches/com.apple.wallpaper.caches"
    }

    /// Folders whose changes mean the wallpaper may have changed. The snapshot
    /// cache too: a render can land a moment after Index.plist changes.
    public static var watchDirectories: [String] { [storeDirectory, snapshotCache] }

    public struct Lookup: Sendable {
        public var path: String?
        /// Why nothing was found, for the user.
        public var notice: String?
        /// How it was found, for `--verbose`.
        public var trace: [String]
    }

    /// The current wallpaper's image file.
    public static func current() -> Lookup {
        var trace: [String] = []
        // With several displays, the one chosen in the settings (default: the
        // one with the menu bar) decides.
        let display = Displays.resolve(TintSettings.load().display)
        if let display, Displays.all().count > 1 {
            trace.append("display \(display.index): \(display.name)")
        }
        let store = readStore(display: display?.uuid)
        trace.append("Index.plist → file: \(store.file ?? "none"), provider: \(store.provider ?? "none")")

        // Pictures and photos: the store first. It is read fresh from disk
        // every time, while what AppKit reports can stay stale inside a
        // long-running process (the login service) — it saw only the first change.
        let isPicture = store.provider.map { $0.contains(".image") || $0.contains("dynamic") } ?? true
        if isPicture {
            if let file = store.file, TintPaths.exists(file) {
                return Lookup(path: file, notice: nil, trace: trace)
            }
            if let reported = reportedImage(display: display?.id) {
                trace.append("macOS reports \(reported)")
                return Lookup(path: reported, notice: nil, trace: trace)
            }
        }

        // No image file at all: use the snapshot macOS rendered of it.
        if let provider = store.provider {
            for folder in MacWallpaperStore.snapshotFolderNames(provider: provider) {
                if let snapshot = MacWallpaperStore.newestSnapshot(in: snapshotCache + "/" + folder, size: display.map { ($0.pixelWidth, $0.pixelHeight) }) {
                    trace.append("using macOS's rendered snapshot: \(snapshot)")
                    return Lookup(path: snapshot, notice: nil, trace: trace)
                }
            }
        }

        if !isPicture, let reported = reportedImage(display: display?.id) {
            trace.append("no snapshot; macOS reports \(reported)")
            return Lookup(path: reported, notice: nil, trace: trace)
        }

        let notice = store.provider.map {
            "the current wallpaper is \(MacWallpaperStore.describe(provider: $0)), and macOS hasn't saved a snapshot of it yet — "
                + "there's nothing to take colours from. Choose a photo or picture as the wallpaper and tint will pick it up."
        } ?? "couldn't find an image file for the current wallpaper."
        return Lookup(path: nil, notice: notice, trace: trace)
    }

    static func readStore(display: String?) -> MacWallpaperStore.Choice {
        guard let data = FileManager.default.contents(atPath: storeDirectory + "/Store/Index.plist") else {
            return MacWallpaperStore.Choice(file: nil, provider: nil)
        }
        return MacWallpaperStore.read(plist: data, display: display)
    }

    /// The image file macOS reports for the main screen, if it is a real file.
    static func reportedImage(display: UInt32?) -> String? {
        #if os(macOS)
        let url: URL? = onMain {
            let chosen = NSScreen.screens.first {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display
            }
            guard let screen = chosen ?? NSScreen.main ?? NSScreen.screens.first else { return nil }
            return NSWorkspace.shared.desktopImageURL(for: screen)
        }
        guard let url, url.isFileURL, !TintPaths.isDirectory(url.path), TintPaths.exists(url.path) else { return nil }
        return url.path
        #else
        return nil
        #endif
    }

    public enum SetError: Error, CustomStringConvertible {
        case notFound(String)
        case failed(String)
        case unsupported

        public var description: String {
            switch self {
            case .notFound(let path): "no such image: \(path)"
            case .failed(let why): "couldn't set the wallpaper: \(why)"
            case .unsupported: "setting the wallpaper works on macOS only"
            }
        }
    }

    /// Makes `path` the desktop picture on every display.
    public static func set(_ path: String) throws {
        #if os(macOS)
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard TintPaths.exists(url.path) else { throw SetError.notFound(url.path) }
        let failure: String? = onMain {
            do {
                for screen in NSScreen.screens {
                    let options = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
                    try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options)
                }
                return nil
            } catch {
                return error.localizedDescription
            }
        }
        if let failure { throw SetError.failed(failure) }
        #else
        throw SetError.unsupported
        #endif
    }

    #if os(macOS)
    /// AppKit's screen APIs belong to the main thread. The CLI runs its main
    /// queue (see `tint watch`), so this works from any thread.
    static func onMain<T: Sendable>(_ body: @MainActor () -> T) -> T {
        if Thread.isMainThread { return MainActor.assumeIsolated(body) }
        return DispatchQueue.main.sync { MainActor.assumeIsolated(body) }
    }
    #endif
}
