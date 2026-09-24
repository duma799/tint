public enum ThemeMode: String, Sendable, CaseIterable, Codable {
    case dark
    case light
}

/// A terminal colour scheme in pywal's shape: background, foreground, cursor,
/// and 16 colours. 0 is the background, 1–6 red, green, yellow, blue, magenta,
/// cyan, 7 dim foreground, 8 "bright black", 9–14 brighter 1–6, 15 foreground.
public struct Scheme: Hashable, Sendable {
    public var background: Rgb
    public var foreground: Rgb
    public var cursor: Rgb
    public var colors: [Rgb]
    public var mode: ThemeMode

    public init(background: Rgb, foreground: Rgb, cursor: Rgb, colors: [Rgb], mode: ThemeMode) {
        precondition(colors.count == 16, "a scheme has 16 colours")
        self.background = background
        self.foreground = foreground
        self.cursor = cursor
        self.colors = colors
        self.mode = mode
    }

    public subscript(index: Int) -> Rgb { colors[index] }
}
