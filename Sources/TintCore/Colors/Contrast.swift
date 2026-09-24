/// WCAG 2 contrast. 4.5 is the minimum for normal text to be comfortably
/// readable, 3 for large text and UI borders, 7 for "enhanced".
public enum Contrast {
    public static let text = 4.5
    public static let large = 3.0
    public static let enhanced = 7.0

    /// Relative luminance, 0 (black) to 1 (white).
    public static func luminance(_ c: Rgb) -> Double {
        0.2126 * Lab.linear(c.r) + 0.7152 * Lab.linear(c.g) + 0.0722 * Lab.linear(c.b)
    }

    /// Contrast ratio between two colours, 1 (identical) to 21 (black on white).
    public static func ratio(_ a: Rgb, _ b: Rgb) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
