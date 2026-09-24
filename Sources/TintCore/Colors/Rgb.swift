/// An sRGB colour with 8 bits per channel — what images and terminals use.
public struct Rgb: Hashable, Sendable, CustomStringConvertible {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// Parses `#rrggbb` or `rrggbb`.
    public init?(hex: String) {
        var s = Substring(hex.trimmingWhitespace())
        if s.hasPrefix("#") { s = s.dropFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        self.init(UInt8((value >> 16) & 0xff), UInt8((value >> 8) & 0xff), UInt8(value & 0xff))
    }

    /// Lower-case hex, e.g. `#1b2233`.
    public var hex: String { "#" + Rgb.byteHex(r) + Rgb.byteHex(g) + Rgb.byteHex(b) }

    /// Hex without the `#`, e.g. `1b2233`.
    public var strip: String { String(hex.dropFirst()) }

    public var lab: Lab { Lab(rgb: self) }

    public var description: String { hex }

    static func byteHex(_ value: UInt8) -> String {
        let s = String(value, radix: 16)
        return s.count == 1 ? "0" + s : s
    }
}

extension String {
    func trimmingWhitespace() -> String {
        var s = Substring(self)
        while let first = s.first, first.isWhitespace { s.removeFirst() }
        while let last = s.last, last.isWhitespace { s.removeLast() }
        return String(s)
    }
}
