import Foundation

/// The defaults `tint apply` and `tint watch` use when no option is given,
/// saved in `~/.config/tint/settings.json`. The app writes them, so a mode
/// picked there sticks for the login service too.
public struct TintSettings: Equatable, Sendable {
    /// Dark or light; nil picks from the image's brightness ("auto").
    public var mode: ThemeMode? = .dark

    /// Accent saturation, see `SchemeBuilder.build`.
    public var saturation: Double = 1

    public init(mode: ThemeMode? = .dark, saturation: Double = 1) {
        self.mode = mode
        self.saturation = saturation
    }

    public static var defaultPath: String { TintPaths.config + "/settings.json" }

    /// "dark", "light" or "auto".
    public static func modeName(_ mode: ThemeMode?) -> String { mode?.rawValue ?? "auto" }

    /// The reverse of `modeName`; anything unknown is dark.
    public static func parseMode(_ name: String?) -> ThemeMode? {
        switch name {
        case "light": .light
        case "auto": nil
        default: .dark
        }
    }

    /// Reads the settings. A missing or broken file gives the defaults: settings must never stop a theme.
    public static func load(from path: String = defaultPath) -> TintSettings {
        var settings = TintSettings()
        guard let data = FileManager.default.contents(atPath: path),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return settings }

        if let mode = root["mode"] as? String {
            settings.mode = parseMode(mode)
        }
        if let saturation = root["saturation"] as? Double {
            settings.saturation = min(max(saturation, SchemeBuilder.saturationRange.lowerBound), SchemeBuilder.saturationRange.upperBound)
        }
        return settings
    }

    public func save(to path: String = defaultPath) throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let rounded = (saturation * 100).rounded() / 100
        let json = "{\n  \"mode\": \"\(TintSettings.modeName(mode))\",\n  \"saturation\": \(rounded)\n}\n"
        try PywalWriter.atomicWrite(json, to: path)
    }
}

extension TintSettings: CustomStringConvertible {
    public var description: String {
        let s = (saturation * 100).rounded() / 100
        return "\(TintSettings.modeName(mode)), saturation \(s == s.rounded() ? String(Int(s)) : String(s))"
    }
}
