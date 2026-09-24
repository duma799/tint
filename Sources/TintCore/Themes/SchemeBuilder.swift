/// Turns a palette into a `Scheme`. Two things pywal doesn't do: accents are
/// matched to their terminal role by hue (the reddest colour goes in the red
/// slot, and so on), and every colour is nudged until it is readable against
/// the background.
public enum SchemeBuilder {
    /// Hue each ANSI slot (1–6) aims for, in Lab degrees:
    /// red, green, yellow, blue, magenta, cyan.
    private static let slotHues: [Double] = [30, 135, 95, 280, 330, 200]

    /// Lowest and highest `saturation` accepted by `build`.
    public static let saturationRange: ClosedRange<Double> = 0.5...1.5

    public enum BuildError: Error, CustomStringConvertible {
        case emptyPalette
        case saturation(Double)

        public var description: String {
            switch self {
            case .emptyPalette: "the palette has no colours"
            case .saturation(let s): "saturation must be between 0.5 and 1.5, not \(s)"
            }
        }
    }

    /// - Parameter saturation: scales how colourful the accents are: 1 keeps
    ///   the image's own colours, 0.5 is muted, 1.5 vivid. Contrast is still
    ///   checked afterwards.
    public static func build(_ palette: Palette, mode: ThemeMode, saturation: Double = 1) throws -> Scheme {
        guard !palette.swatches.isEmpty else { throw BuildError.emptyPalette }
        guard saturationRange.contains(saturation) else { throw BuildError.saturation(saturation) }

        let dark = mode == .dark
        let labs = palette.swatches.map(\.lab)
        let darkest = labs.min { $0.l < $1.l }!
        let lightest = labs.max { $0.l < $1.l }!

        // Background and foreground keep a hint of the image's tint, but only a
        // hint: strongly coloured backgrounds make every other colour muddy.
        let backgroundLab = dark
            ? darkest.withLightness(min(darkest.l, 12)).withMaxChroma(12)
            : lightest.withLightness(max(lightest.l, 94)).withMaxChroma(8)
        let background = backgroundLab.rgb

        let foregroundLab = dark
            ? lightest.withLightness(max(lightest.l, 88)).withMaxChroma(10)
            : darkest.withLightness(min(darkest.l, 22)).withMaxChroma(12)
        let foreground = readable(foregroundLab, on: background, ratio: Contrast.enhanced, lighten: dark)

        // Accents stay in a mid-lightness band, so none reads as black (on a
        // light theme) or white (on a dark one) — a navy "blue" is still blue.
        let accents = pickAccents(labs, background: backgroundLab, foreground: foregroundLab).map { a in
            Lab(l: dark ? min(a.l, 78) : max(a.l, 40), a: a.a * saturation, b: a.b * saturation)
        }

        var colors = [Rgb](repeating: background, count: 16)
        for i in 0..<6 {
            colors[i + 1] = readable(accents[i], on: background, ratio: Contrast.text, lighten: dark)
            let bright = accents[i].withLightness(min(max(accents[i].l + (dark ? 8 : -8), 0), 100))
            colors[i + 9] = readable(bright, on: background, ratio: Contrast.text, lighten: dark)
        }
        colors[7] = readable(foregroundLab.withLightness(foregroundLab.l + (dark ? -12 : 12)), on: background, ratio: Contrast.text, lighten: dark)
        colors[8] = readable(backgroundLab.withLightness(backgroundLab.l + (dark ? 18 : -18)), on: background, ratio: Contrast.large, lighten: dark)
        colors[15] = foreground

        return Scheme(background: background, foreground: foreground, cursor: foreground, colors: colors, mode: mode)
    }

    /// Six accent colours, one per ANSI slot. The image's most colourful,
    /// mutually distinct colours are matched to the slot whose hue they're
    /// closest to; any slot left over gets a colour made from the image's
    /// average tint at that slot's hue, so monochrome wallpapers still yield a
    /// usable scheme.
    private static func pickAccents(_ labs: [Lab], background: Lab, foreground: Lab) -> [Lab] {
        let minChroma = 12.0
        let minDistance = 12.0

        // A colour this far from a slot's hue would change its meaning (a brown
        // "blue" makes `ls` folders brown), so that slot gets a made colour instead.
        let maxHueDistance = 70.0

        var candidates: [Lab] = []
        for lab in labs.sorted(by: { $0.chroma > $1.chroma }) {
            if lab.chroma < minChroma
                || lab.distance(to: background) < minDistance
                || lab.distance(to: foreground) < minDistance
                || candidates.contains(where: { $0.distance(to: lab) < minDistance }) {
                continue
            }
            candidates.append(lab)
        }

        // Greedy matching: the closest (slot, colour) pairs by hue go first.
        var pairs: [(slot: Int, index: Int, distance: Double)] = []
        for slot in 0..<6 {
            for index in candidates.indices {
                let d = hueDistance(candidates[index].hue, slotHues[slot])
                if d <= maxHueDistance { pairs.append((slot, index, d)) }
            }
        }
        pairs.sort { ($0.distance, $0.slot, $0.index) < ($1.distance, $1.slot, $1.index) }

        var accents = [Lab?](repeating: nil, count: 6)
        var used = [Bool](repeating: false, count: candidates.count)
        for pair in pairs where accents[pair.slot] == nil && !used[pair.index] {
            accents[pair.slot] = candidates[pair.index]
            used[pair.index] = true
        }

        // Fill empty slots from the image's overall character: its typical
        // lightness and a modest chroma, at the slot's own hue.
        let lightness = candidates.isEmpty ? 65 : candidates.map(\.l).reduce(0, +) / Double(candidates.count)
        let averageChroma = candidates.isEmpty ? 25 : candidates.map(\.chroma).reduce(0, +) / Double(candidates.count)
        let chroma = min(max(averageChroma, 20), 45)

        return (0..<6).map { slot in
            accents[slot] ?? Lab.lch(l: lightness, chroma: chroma, hue: slotHues[slot])
        }
    }

    /// Moves `color` lighter (dark themes) or darker (light themes) until it
    /// reaches `ratio` against the background. Hue and chroma are kept, so it's
    /// the same colour, just legible.
    static func readable(_ color: Lab, on background: Rgb, ratio: Double, lighten: Bool) -> Rgb {
        var current = color.withLightness(min(max(color.l, 0), 100))
        for _ in 0...100 {
            let rgb = current.rgb
            if Contrast.ratio(rgb, background) >= ratio { return rgb }
            let l = current.l + (lighten ? 1 : -1)
            if l < 0 || l > 100 { break }
            current = current.withLightness(l)
        }

        // Out of room at the end of the lightness scale: plain white/black.
        return lighten ? Rgb(255, 255, 255) : Rgb(0, 0, 0)
    }

    private static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return d > 180 ? 360 - d : d
    }
}
