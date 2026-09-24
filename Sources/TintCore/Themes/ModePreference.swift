import Foundation

/// How to pick dark or light: fixed, from the image, or from macOS.
public enum ModePreference: String, CaseIterable, Sendable {
    case dark
    case light
    /// From the image's brightness.
    case auto
    /// Whatever macOS uses now (System Settings → Appearance), including
    /// when it switches by itself at sunset.
    case system

    /// Parses a name; anything unknown is dark.
    public init(name: String?) {
        self = name.flatMap(ModePreference.init(rawValue:)) ?? .dark
    }

    /// The scheme mode for this image, now.
    public func resolve(for palette: Palette, systemIsDark: () -> Bool = SystemAppearance.isDark) -> ThemeMode {
        switch self {
        case .dark: .dark
        case .light: .light
        case .auto: palette.isDark ? .dark : .light
        case .system: systemIsDark() ? .dark : .light
        }
    }
}

/// macOS's own dark/light setting.
public enum SystemAppearance {
    /// True when macOS is in dark mode. Asked fresh every time (a long-running
    /// process would otherwise keep the answer it read first).
    public static func isDark() -> Bool {
        #if os(macOS)
        // `defaults read -g AppleInterfaceStyle` prints "Dark" in dark mode and
        // fails in light mode; with Appearance set to Auto, macOS updates it
        // when it switches.
        let result = try? ProcessRunner.run("defaults", ["read", "-g", "AppleInterfaceStyle"])
        return result?.succeeded == true && result?.stdout == "Dark"
        #else
        return true
        #endif
    }

    #if os(macOS)
    /// The notification macOS posts when it switches between dark and light.
    public static let changedNotification = Notification.Name("AppleInterfaceThemeChangedNotification")
    #endif
}
