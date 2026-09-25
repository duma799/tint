import Foundation

#if os(macOS)
import AppKit
import CoreGraphics
#endif

/// A connected display.
public struct DisplayInfo: Sendable, Equatable {
    /// 1, 2, … in macOS's order; the main display (with the menu bar) is 1.
    public var index: Int
    public var id: UInt32
    /// The UUID macOS uses for this display in the wallpaper store.
    public var uuid: String
    public var name: String
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var isMain: Bool
}

/// The displays, and which one's wallpaper tint themes from.
public enum Displays {
    /// Every active display, main first.
    public static func all() -> [DisplayInfo] {
        #if os(macOS)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        let main = CGMainDisplayID()
        ids.sort { ($0 == main ? 0 : 1, $0) < ($1 == main ? 0 : 1, $1) }

        let names: [UInt32: String] = MacWallpaper.onMain {
            var names: [UInt32: String] = [:]
            for screen in NSScreen.screens {
                if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                    names[number.uint32Value] = screen.localizedName
                }
            }
            return names
        }

        return ids.enumerated().map { i, id in
            let uuid = CGDisplayCreateUUIDFromDisplayID(id).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String } ?? ""
            let mode = CGDisplayCopyDisplayMode(id)
            return DisplayInfo(
                index: i + 1, id: id, uuid: uuid, name: names[id] ?? "Display \(i + 1)",
                pixelWidth: mode?.pixelWidth ?? Int(CGDisplayPixelsWide(id)),
                pixelHeight: mode?.pixelHeight ?? Int(CGDisplayPixelsHigh(id)),
                isMain: id == main)
        }
        #else
        return []
        #endif
    }

    /// The display a setting names: "main" (or nothing), a number from
    /// `tint displays`, or part of a display's name. Falls back to the main
    /// display if that display isn't connected.
    public static func resolve(_ selector: String?, among displays: [DisplayInfo]? = nil) -> DisplayInfo? {
        let displays = displays ?? all()
        let main = displays.first { $0.isMain } ?? displays.first
        guard let selector, !selector.isEmpty, selector != "main" else { return main }
        if let n = Int(selector) { return displays.first { $0.index == n } ?? main }
        return displays.first { $0.name.localizedCaseInsensitiveContains(selector) } ?? main
    }
}
