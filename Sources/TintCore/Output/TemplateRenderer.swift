/// Renders pywal-style templates, so existing `~/.config/wal/templates` keep
/// working unchanged.
///
/// Syntax (Python `str.format`, as pywal uses):
/// - `{color4}` → `#1b2233`; also `background`, `foreground`, `cursor`, `color0`–`color15`
/// - `{color4.strip}` → `1b2233`, `.rgb` → `27,34,51`, `.rgba` → `27,34,51,1.0`,
///   `.xrgba` → `1b/22/33/ff`, `.red`/`.green`/`.blue` → `0.106`
/// - `{wallpaper}`, `{alpha}` (`100`), `{alpha.decimal}` (`1.0`)
/// - `{{` and `}}` → literal braces
///
/// Anything unrecognised is left exactly as written and reported.
public enum TemplateRenderer {
    public struct Result: Sendable {
        public var text: String
        public var unknown: [String]
    }

    public static func render(_ template: String, scheme: Scheme, wallpaper: String) -> Result {
        let chars = Array(template)
        var output = ""
        output.reserveCapacity(chars.count + 256)
        var unknown: [String] = []
        var i = 0

        func next(_ expected: Character) -> Bool { i + 1 < chars.count && chars[i + 1] == expected }

        while i < chars.count {
            let c = chars[i]
            if c == "{" && next("{") {
                output.append("{")
                i += 2
            } else if c == "}" && next("}") {
                output.append("}")
                i += 2
            } else if c == "{" {
                let close = chars[(i + 1)...].firstIndex(of: "}")
                if let close, let value = resolve(String(chars[(i + 1)..<close]), scheme: scheme, wallpaper: wallpaper) {
                    output += value
                    i = close + 1
                } else {
                    // Not ours: keep it verbatim, so nothing is silently mangled.
                    unknown.append(close.map { String(chars[i...$0]) } ?? String(chars[i..<min(chars.count, i + 20)]))
                    output.append(c)
                    i += 1
                }
            } else {
                output.append(c)
                i += 1
            }
        }

        return Result(text: output, unknown: unknown)
    }

    private static func resolve(_ token: String, scheme: Scheme, wallpaper: String) -> String? {
        let parts = token.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let name = String(parts[0])
        let modifier = parts.count > 1 ? String(parts[1]) : nil

        switch (name, modifier) {
        case ("wallpaper", nil): return wallpaper
        case ("alpha", nil): return "100"
        case ("alpha", "decimal"): return "1.0"
        default: break
        }

        let color: Rgb?
        switch name {
        case "background": color = scheme.background
        case "foreground": color = scheme.foreground
        case "cursor": color = scheme.cursor
        default:
            if name.hasPrefix("color"), let n = Int(name.dropFirst(5)), (0..<16).contains(n),
               name.dropFirst(5).allSatisfy(\.isASCII) {
                color = scheme[n]
            } else {
                color = nil
            }
        }

        return color.flatMap { format($0, modifier) }
    }

    private static func format(_ c: Rgb, _ modifier: String?) -> String? {
        switch modifier {
        case nil: c.hex
        case "strip": c.strip
        case "rgb": "\(c.r),\(c.g),\(c.b)"
        case "rgba": "\(c.r),\(c.g),\(c.b),1.0"
        case "xrgba": "\(Rgb.byteHex(c.r))/\(Rgb.byteHex(c.g))/\(Rgb.byteHex(c.b))/ff"
        case "red": unit(c.r)
        case "green": unit(c.g)
        case "blue": unit(c.b)
        default: nil
        }
    }

    /// 0...255 → "0.000"..."1.000", without Foundation's locale-dependent formatting.
    private static func unit(_ channel: UInt8) -> String {
        let thousandths = Int((Double(channel) / 255 * 1000).rounded())
        let fraction = String(thousandths % 1000)
        return "\(thousandths / 1000)." + String(repeating: "0", count: 3 - fraction.count) + fraction
    }
}
