import Foundation
import Testing
@testable import TintCore

struct OutputTests {
    let s = testScheme

    @Test func colourPlaceholdersRender() {
        #expect(TemplateRenderer.render("{color4}", scheme: s, wallpaper: "/w.jpg").text == s[4].hex)
        #expect(TemplateRenderer.render("{color4.strip}", scheme: s, wallpaper: "/w.jpg").text == s[4].strip)
    }

    @Test func modifiersBracesAndSpecialsRenderLikePywal() {
        let bg = s.background
        let text = TemplateRenderer.render(
            "{{ {background.rgb} | {background.xrgba} | {wallpaper} | {alpha} | {alpha.decimal} | {color1.red} }}",
            scheme: s, wallpaper: "/w.jpg").text
        let red = String(format: "%.3f", Double(s[1].r) / 255)
        #expect(text == "{ \(bg.r),\(bg.g),\(bg.b) | \(bg.strip.prefix(2))/\(bg.strip.dropFirst(2).prefix(2))/\(bg.strip.suffix(2))/ff | /w.jpg | 100 | 1.0 | \(red) }")
    }

    @Test func unknownPlaceholdersAreKeptAndReported() {
        let result = TemplateRenderer.render("a {nope} b {color99} c {unclosed", scheme: s, wallpaper: "/w.jpg")
        #expect(result.text == "a {nope} b {color99} c {unclosed")
        #expect(result.unknown.count == 3)
    }

    @Test func aSketchybarTemplateRendersArgbAndLiteralBraces() {
        let template = "export ACCENT_COLOR=0xff{color4.strip}\nbar_color() {{ printf '%s\\n' \"$BAR_COLOR\"; }}\n"
        let text = TemplateRenderer.render(template, scheme: s, wallpaper: "/w.jpg").text
        #expect(text.contains("export ACCENT_COLOR=0xff\(s[4].strip)"))
        #expect(text.contains("bar_color() { printf"))
    }

    @Test func writesEveryFilePlusTemplates() throws {
        let dir = TempDir()
        dir.write("templates/sketchybar-colors.sh", "export ACCENT=0xff{color4.strip}\n")
        let result = try PywalWriter.write(s, wallpaper: "/walls/city.jpg", to: dir.file("wal"), templates: dir.file("templates"))

        let names = result.written.map { ($0 as NSString).lastPathComponent }.sorted()
        #expect(names == ["colors", "colors-ghostty", "colors-kitty.conf", "colors-wal.vim", "colors-wezterm.toml",
                          "colors.css", "colors.json", "colors.sh", "sketchybar-colors.sh", "wal"])
        #expect(result.warnings.isEmpty)
        #expect(dir.read("wal/sketchybar-colors.sh") == "export ACCENT=0xff\(s[4].strip)\n")
    }

    @Test func colorsJsonHasPywalsStructure() throws {
        let json = PywalWriter.json(s, "/walls/a \"quoted\" name.jpg")
        let root = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        #expect(root["wallpaper"] as? String == "/walls/a \"quoted\" name.jpg")
        #expect((root["special"] as? [String: String])?["background"] == s.background.hex)
        #expect((root["colors"] as? [String: String])?.count == 16)
        #expect((root["colors"] as? [String: String])?["color15"] == s[15].hex)
    }

    @Test func plainColourAndVimFilesMatchPywal() {
        #expect(PywalWriter.vim(s, "/w.jpg").contains("let color4  = \"\(s[4].hex)\"\n"))
        #expect(PywalWriter.kitty(s).contains("color15  \(s[15].hex)\n"))
    }

    @Test func awkwardPathsCannotBreakOutOfStrings() {
        let path = "/walls/it's \"odd\"\\\nname.jpg"
        #expect(PywalWriter.shell(s, path).contains("wallpaper='/walls/it'\\''s"))
        #expect(PywalWriter.vim(s, path).contains("let wallpaper  = \"/walls/it's \\\"odd\\\"\\\\\\nname.jpg\""))
        #expect(PywalWriter.css(s, path).contains("url(\"/walls/it's \\\"odd\\\"\\\\\\A name.jpg\")"))
    }

    @Test func writesGhosttyAndWeztermThemes() {
        let ghostty = PywalWriter.ghostty(s)
        #expect(ghostty.contains("background = \(s.background.hex)\n"))
        #expect(ghostty.contains("palette = 15=\(s[15].hex)\n"))
        let wezterm = PywalWriter.wezterm(s)
        #expect(wezterm.contains("ansi = [\"\(s[0].hex)\", "))
        #expect(wezterm.contains("brights = [\"\(s[8].hex)\", "))
    }

    @Test func apolloShellThemeUsesTheSchemeAndOnlyItsOwnTokens() throws {
        let css = ApolloShellTheme.render(s, wallpaper: "/walls/koi */ evil.jpg")
        #expect(css.contains("--apollo-accent-color: \(s[4].hex);"))
        #expect(css.contains("--apollo-background-color: \(s.background.hex);"))
        #expect(css.contains("--apollo-theme-appearance: dark;"))
        #expect(!css.contains("*/ evil"))
        let declarations = css.split(separator: "\n").filter { $0.contains(":") && $0.hasPrefix("  ") }
        #expect(declarations.allSatisfy { $0.hasPrefix("  --apollo-") })
    }

    @Test func apolloShellThemeIsWrittenOnlyWhenApolloShellIsInstalled() throws {
        let dir = TempDir()
        #expect(try ApolloShellTheme.write(s, wallpaper: "/w.jpg", themesDirectory: dir.file("ApolloShell/themes")) == nil)
        try FileManager.default.createDirectory(atPath: dir.file("ApolloShell"), withIntermediateDirectories: true)
        #expect(try ApolloShellTheme.write(s, wallpaper: "/w.jpg", themesDirectory: dir.file("ApolloShell/themes")) == dir.file("ApolloShell/themes/tint.css"))
    }
}
