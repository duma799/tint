import Foundation

/// Reads macOS's wallpaper store (`Index.plist`). Plain parsing with no macOS
/// calls, so it is unit-tested on every platform.
///
/// Shape on macOS 26, per desktop "choice":
/// ```
/// AllSpacesAndDisplays/Desktop/Content/Choices[0]/
///     Provider       "com.apple.wallpaper.choice.image"
///     Files          []            ← empty, even for a picture
///     Configuration  <data>        ← a second, nested plist holding the file URL
/// ```
public enum MacWallpaperStore {
    /// The desktop wallpaper found in Index.plist: its image file (if known)
    /// and its provider id.
    public struct Choice: Equatable, Sendable {
        public var file: String?
        public var provider: String?
    }

    /// One value in a plist with the key path leading to it.
    struct Leaf {
        var path: String
        var key: String
        var string: String?
        var data: Data?
        var date: Date?
    }

    /// Reads a store plist (binary or XML), following the nested configuration.
    /// - Parameter display: the display's UUID, to pick its own wallpaper when
    ///   displays have different ones; nil considers every display.
    public static func read(plist data: Data, display: String? = nil) -> Choice {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) else {
            return Choice(file: nil, provider: nil)
        }
        let (choice, configuration) = pickDesktopChoice(flatten(root), display: display)

        // A picture's path isn't in "Files" but in "Configuration": a second
        // plist nested inside the first. Unpack that one too.
        if choice.file == nil, let configuration,
           let nested = try? PropertyListSerialization.propertyList(from: configuration, format: nil) {
            return Choice(file: findFileURL(flatten(nested)), provider: choice.provider)
        }
        return choice
    }

    /// Picks the desktop (not screen saver) wallpaper for a display.
    ///
    /// Each place a wallpaper can be set — all displays, one display, one
    /// space — is a "slot" with its own `LastSet` date. The most recently set
    /// slot that applies to the display wins: that's what's on screen, even
    /// when older per-display settings are still stored. Without dates, the
    /// all-displays setting wins, then per-display ones, then document order.
    static func pickDesktopChoice(_ leaves: [Leaf], display: String? = nil) -> (Choice, configuration: Data?) {
        let sectionOrder = ["AllSpacesAndDisplays", "Displays", "Spaces", "SystemDefault"]

        struct Slot {
            var prefix: String      // e.g. "Displays/<uuid>/Desktop/"
            var rank: Int
            var order: Int
            var date: Date?
            var provider: Leaf
        }

        var slots: [Slot] = []
        for (order, leaf) in leaves.enumerated() where leaf.key == "Provider" && leaf.string != nil {
            let parts = leaf.path.split(separator: "/").map(String.init)
            guard let desktop = parts.firstIndex(where: { $0 == "Desktop" }) else { continue }
            let section = parts.first ?? ""
            // Another display's own wallpaper doesn't apply to this one.
            if section == "Displays", let display, parts.count > 1, parts[1].caseInsensitiveCompare(display) != .orderedSame { continue }
            let slotPath = parts[...desktop].joined(separator: "/")
            let date = leaves.first { $0.path == slotPath + "/LastSet" }?.date
            slots.append(Slot(prefix: slotPath + "/", rank: sectionOrder.firstIndex(of: section) ?? sectionOrder.count,
                              order: order, date: date, provider: leaf))
        }

        let best = slots.min { a, b in
            switch (a.date, b.date) {
            case let (x?, y?) where x != y: return x > y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return (a.rank, a.order) < (b.rank, b.order)
            }
        }
        guard let best else { return (Choice(file: nil, provider: nil), nil) }

        // Everything else must come from the same choice as the provider.
        let prefix = String(best.provider.path[..<best.provider.path.lastIndex(of: "/")!]) + "/"
        let own = leaves.filter { $0.path.hasPrefix(prefix) }
        let file = findFileURL(own.filter { $0.key == "relative" })
        let configuration = own.first { $0.key == "Configuration" && ($0.data?.isEmpty == false) }?.data
        return (Choice(file: file, provider: best.provider.string), configuration)
    }

    /// The first `file://` URL among the string values, as a local path.
    static func findFileURL(_ leaves: [Leaf]) -> String? {
        leaves.lazy.compactMap(\.string).first { $0.hasPrefix("file://") }.flatMap { URL(string: $0)?.path }
    }

    /// Flattens a plist into its values, e.g. `AllSpacesAndDisplays/Desktop/Content/Choices[0]/Provider`.
    static func flatten(_ root: Any) -> [Leaf] {
        var leaves: [Leaf] = []
        func walk(_ value: Any, path: String, key: String) {
            switch value {
            case let s as String:
                leaves.append(Leaf(path: path, key: key, string: s))
            case let d as Data:
                leaves.append(Leaf(path: path, key: key, data: d))
            case let d as Date:
                leaves.append(Leaf(path: path, key: key, date: d))
            case let dict as [String: Any]:
                // Sorted, so "document order" is stable (dictionaries have none).
                for k in dict.keys.sorted() {
                    walk(dict[k]!, path: path.isEmpty ? k : "\(path)/\(k)", key: k)
                }
            case let array as [Any]:
                for (i, element) in array.enumerated() { walk(element, path: "\(path)[\(i)]", key: key) }
            default:
                break
            }
        }
        walk(root, path: "", key: "")
        return leaves
    }

    static let snapshotExtensions: Set<String> = ["bmp", "png", "jpg", "jpeg", "heic", "tiff"]

    /// Cache folder names macOS may use for a provider. Extensions use their own
    /// id (`com.apple.NeptuneOneExtension`); the built-in picture provider
    /// `com.apple.wallpaper.choice.image` caches under
    /// `com.apple.wallpaper.extension.image`.
    public static func snapshotFolderNames(provider: String) -> [String] {
        var names = ["extension-\(provider)"]
        if provider.contains(".choice.") {
            names.append("extension-" + provider.replacingAll(".choice.", with: ".extension."))
        }
        return names
    }

    /// The newest rendered snapshot in a cache folder. macOS draws the current
    /// wallpaper there (one image per display size), so the most recent one is
    /// what's on screen now — even for wallpapers with no image file, like the
    /// macOS 26 extension wallpapers.
    /// - Parameter size: the display's size in pixels; a render of that size
    ///   (its name has "-<width>-<height>-") is preferred when there are several.
    public static func newestSnapshot(in folder: String, size: (Int, Int)? = nil) -> String? {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: folder) else { return nil }
        let candidates: [(path: String, date: Date, size: Int)] = names.compactMap { name in
            guard snapshotExtensions.contains((name as NSString).pathExtension.lowercased()) else { return nil }
            let path = folder + "/" + name
            guard let attributes = try? fm.attributesOfItem(atPath: path),
                  let size = (attributes[.size] as? NSNumber)?.intValue, size > 0,
                  let date = attributes[.modificationDate] as? Date
            else { return nil }
            return (path, date, size)
        }
        let sized = size.map { w, h in candidates.filter { ($0.path as NSString).lastPathComponent.contains("-\(w)-\(h)-") } } ?? []
        // Newest first; same moment: prefer the larger (main display) render.
        return (sized.isEmpty ? candidates : sized).max { ($0.date, $0.size) < ($1.date, $1.size) }?.path
    }

    /// Words for a provider with no image file, for messages.
    public static func describe(provider: String) -> String {
        let p = provider.lowercased()
        if p.contains("aerial") { return "an aerial video" }
        if p.contains("color") { return "a solid colour" }
        if p.contains("image") { return "a picture tint couldn't locate" }
        return "a built-in dynamic wallpaper (\(provider))"
    }
}
