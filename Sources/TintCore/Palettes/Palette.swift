/// One palette colour and the share of the image it covers (0...1).
public struct Swatch: Hashable, Sendable {
    public var color: Rgb
    public var share: Double

    public init(color: Rgb, share: Double) {
        self.color = color
        self.share = share
    }

    public var lab: Lab { color.lab }
}

/// The colours extracted from an image, most common first.
public struct Palette: Hashable, Sendable {
    public var swatches: [Swatch]

    public init(swatches: [Swatch]) { self.swatches = swatches }

    /// Average lightness weighted by coverage, 0...100. Below ~50 reads as a dark image.
    public var lightness: Double { swatches.reduce(0) { $0 + $1.lab.l * $1.share } }

    public var isDark: Bool { lightness < 50 }
}
