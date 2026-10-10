public enum ThemeMode: String, Sendable, CaseIterable, Codable {
    case dark
    case light
}

/// A terminal colour scheme in pywal's shape: background, foreground, cursor,
/// and 16 colours. 0 is the background, 1–6 red, green, yellow, blue, magenta,
/// cyan, 7 dim foreground, 8 "bright black", 9–14 brighter 1–6, 15 foreground.
///
/// `accent` is the one colour for things that want a single theme colour (a
/// bar, window borders, the app): the wallpaper's own colour, unlike colour 4,
/// which is a blue whatever the image. It is always one of `colors`.
public struct Scheme: Hashable, Sendable {
    public var background: Rgb
    public var foreground: Rgb
    public var cursor: Rgb
    public var accent: Rgb
    public var colors: [Rgb]
    public var mode: ThemeMode

    public init(background: Rgb, foreground: Rgb, cursor: Rgb, accent: Rgb, colors: [Rgb], mode: ThemeMode) {
        precondition(colors.count == 16, "a scheme has 16 colours")
        self.background = background
        self.foreground = foreground
        self.cursor = cursor
        self.accent = accent
        self.colors = colors
        self.mode = mode
    }

    public subscript(index: Int) -> Rgb { colors[index] }
}
