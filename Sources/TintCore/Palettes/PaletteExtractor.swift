public struct ExtractOptions: Sendable {
    /// How many colours to extract.
    public var count = 16

    /// The image is shrunk so its longer side is at most this many pixels
    /// before clustering. 256 keeps a 5K wallpaper to ~65k pixels — fast, and
    /// the palette barely changes compared with using every pixel.
    public var maxSide = 256

    /// Fixed seed: the same image always produces the same palette.
    public var seed: UInt64 = 7

    public init() {}
}

public enum PaletteError: Error, CustomStringConvertible {
    case empty
    case unreadable(String)

    public var description: String {
        switch self {
        case .empty: "the image has no pixels"
        case .unreadable(let why): why
        }
    }
}

public enum PaletteExtractor {
    /// Clusters already-decoded pixels (at most `maxSide` on the longer side).
    public static func extract(pixels: [Rgb], options: ExtractOptions = ExtractOptions()) throws -> Palette {
        guard !pixels.isEmpty else { throw PaletteError.empty }
        let points = pixels.map(Lab.init(rgb:))
        let clusters = KMeans.run(points, k: options.count, seed: options.seed)
        let total = Double(points.count)
        let swatches = clusters
            .sorted { $0.count > $1.count }
            .map { Swatch(color: $0.center.rgb, share: Double($0.count) / total) }
        return Palette(swatches: swatches)
    }

    /// Reads an image file and extracts its palette.
    public static func extract(file path: String, options: ExtractOptions = ExtractOptions()) throws -> Palette {
        let pixels = try ImageLoader.pixels(path: path, maxSide: options.maxSide)
        return try extract(pixels: pixels, options: options)
    }
}
