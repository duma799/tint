import Foundation

/// A colour in CIELAB (D65). Unlike RGB, straight-line distance here roughly
/// matches how different two colours look to a person, which is what palette
/// clustering needs. `l` is lightness from 0 (black) to 100 (white); `a` runs
/// green→red and `b` blue→yellow.
public struct Lab: Hashable, Sendable {
    public var l: Double
    public var a: Double
    public var b: Double

    public init(l: Double, a: Double, b: Double) {
        self.l = l
        self.a = a
        self.b = b
    }

    // D65 reference white, the white point sRGB is defined against.
    private static let xn = 0.95047
    private static let yn = 1.00000
    private static let zn = 1.08883

    // CIE constants, as exact fractions rather than the rounded 0.008856 / 903.3.
    private static let epsilon = 216.0 / 24389.0
    private static let kappa = 24389.0 / 27.0

    /// sRGB byte → linear light. 256 entries, so conversion avoids pow() per pixel.
    private static let linearTable: [Double] = (0..<256).map { i in
        let c = Double(i) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// sRGB byte → linear light (0...1), shared with the contrast maths.
    static func linear(_ channel: UInt8) -> Double { linearTable[Int(channel)] }

    public init(rgb c: Rgb) {
        let r = Lab.linear(c.r), g = Lab.linear(c.g), b = Lab.linear(c.b)

        // Linear sRGB → CIE XYZ.
        let x = 0.4124564 * r + 0.3575761 * g + 0.1804375 * b
        let y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
        let z = 0.0193339 * r + 0.1191920 * g + 0.9503041 * b

        // XYZ → Lab.
        let fx = Lab.f(x / Lab.xn), fy = Lab.f(y / Lab.yn), fz = Lab.f(z / Lab.zn)
        self.init(l: 116 * fy - 16, a: 500 * (fx - fy), b: 200 * (fy - fz))
    }

    /// Back to sRGB. Colours outside the sRGB gamut are clamped.
    public var rgb: Rgb {
        let fy = (l + 16) / 116
        let fx = fy + a / 500
        let fz = fy - b / 200

        let x = Lab.xn * Lab.fInverse(fx)
        let y = Lab.yn * Lab.fInverse(fy)
        let z = Lab.zn * Lab.fInverse(fz)

        let r = 3.2404542 * x - 1.5371385 * y - 0.4985314 * z
        let g = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z
        let bl = 0.0556434 * x - 0.2040259 * y + 1.0572252 * z
        return Rgb(Lab.toByte(r), Lab.toByte(g), Lab.toByte(bl))
    }

    /// Squared CIE76 ΔE. Cheaper than `distance(to:)` when only comparing.
    @inline(__always)
    public func distanceSquared(to other: Lab) -> Double {
        let dl = l - other.l, da = a - other.a, db = b - other.b
        return dl * dl + da * da + db * db
    }

    /// CIE76 ΔE: about 2.3 is the smallest difference most people notice.
    public func distance(to other: Lab) -> Double { distanceSquared(to: other).squareRoot() }

    /// Colourfulness: 0 for greys, 30+ for clearly coloured, 100+ for vivid.
    public var chroma: Double { (a * a + b * b).squareRoot() }

    /// Hue angle in degrees, 0..<360 (≈40 red, 100 yellow, 136 green, 196 cyan, 306 blue).
    public var hue: Double { (atan2(b, a) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360) }

    /// Builds a colour from lightness, chroma and hue (the LCh form of Lab).
    public static func lch(l: Double, chroma: Double, hue: Double) -> Lab {
        let radians = hue * .pi / 180
        return Lab(l: l, a: chroma * cos(radians), b: chroma * sin(radians))
    }

    /// Same hue, chroma capped at `max`.
    public func withMaxChroma(_ max: Double) -> Lab {
        let c = chroma
        guard c > max, c != 0 else { return self }
        return Lab(l: l, a: a * max / c, b: b * max / c)
    }

    /// The same colour with another lightness.
    public func withLightness(_ value: Double) -> Lab { Lab(l: value, a: a, b: b) }

    private static func f(_ t: Double) -> Double { t > epsilon ? cbrt(t) : (kappa * t + 16) / 116 }

    private static func fInverse(_ t: Double) -> Double {
        let t3 = t * t * t
        return t3 > epsilon ? t3 : (116 * t - 16) / kappa
    }

    private static func toByte(_ linear: Double) -> UInt8 {
        let v = min(max(linear, 0), 1)
        let encoded = v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
        return UInt8((min(max(encoded, 0), 1) * 255).rounded())
    }
}
