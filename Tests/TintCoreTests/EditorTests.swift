import Foundation
import Testing
@testable import TintCore

struct EditorTests {
    let s = testScheme

    func json(_ path: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: FileManager.default.contents(atPath: path)!) as! [String: Any]
    }

    @Test func nothingIsWrittenForEditorsThatAreNotInstalled() {
        let home = TempDir()
        let result = EditorThemes.write(s, paths: .init(home: home.path))
        #expect(result.written.isEmpty && result.warnings.isEmpty)
    }

    @Test func zedGetsAThemeFileAndItsSettingsPointAtIt() throws {
        let home = TempDir()
        home.write(".config/zed/settings.json", """
        {
          "theme": { "mode": "system", "light": "Ayu Light", "dark": "Pywal" },
          "buffer_font_size": 15
        }
        """)
        let result = EditorThemes.write(s, paths: .init(home: home.path))

        let theme = try json(home.file(".config/zed/themes/tint.json"))
        let variant = (theme["themes"] as! [[String: Any]])[0]
        #expect(variant["name"] as? String == "Tint")
        #expect(variant["appearance"] as? String == "dark")
        #expect(((variant["style"] as! [String: Any])["background"] as? String) == s.background.hex)

        let settings = home.read(".config/zed/settings.json")
        #expect(settings.contains("\"dark\": \"Tint\""))
        #expect(settings.contains("\"light\": \"Ayu Light\""))
        #expect(settings.contains("\"buffer_font_size\": 15"))
        #expect(result.written.count == 2)
    }

    @Test func vscodeKeepsOtherSettingsAndGetsTheColours() throws {
        let home = TempDir()
        home.write("Library/Application Support/Code/User/settings.json", "{\"editor.fontSize\": 14}")
        _ = EditorThemes.write(s, paths: .init(home: home.path))

        let settings = try json(home.file("Library/Application Support/Code/User/settings.json"))
        #expect(settings["editor.fontSize"] as? Int == 14)
        let workbench = settings["workbench.colorCustomizations"] as! [String: String]
        #expect(workbench["terminal.ansiBlue"] == s[4].hex)
        #expect(settings["editor.tokenColorCustomizations"] != nil)
    }

    @Test func settingsWithCommentsAreLeftAloneWithAWarning() {
        let home = TempDir()
        let original = "{\n  // my settings\n  \"editor.fontSize\": 14\n}\n"
        home.write("Library/Application Support/Antigravity/User/settings.json", original)
        let result = EditorThemes.write(s, paths: .init(home: home.path))

        #expect(home.read("Library/Application Support/Antigravity/User/settings.json") == original)
        #expect(result.warnings.count == 1)
        #expect(result.warnings[0].hasPrefix("Antigravity"))
    }

    @Test func geminiGetsATintThemeSelected() throws {
        let home = TempDir()
        home.write(".gemini/settings.json", "{\"ui\": {\"showTips\": false}}")
        _ = EditorThemes.write(s, paths: .init(home: home.path))

        let ui = try json(home.file(".gemini/settings.json"))["ui"] as! [String: Any]
        #expect(ui["theme"] as? String == "Tint")
        #expect(ui["showTips"] as? Bool == false)
        #expect(((ui["customThemes"] as! [String: Any])["Tint"] as! [String: Any])["Background"] as? String == s.background.hex)
    }

    @Test func lightSchemesGetLightEditorThemes() throws {
        let light = try SchemeBuilder.build(SchemeTests.night, mode: .light)
        let home = TempDir()
        home.write(".config/zed/settings.json", "{\"theme\": {\"light\": \"One Light\", \"dark\": \"One Dark\"}}")
        _ = EditorThemes.write(light, paths: .init(home: home.path))

        let settings = home.read(".config/zed/settings.json")
        #expect(settings.contains("\"light\": \"Tint\""))
        #expect(settings.contains("\"dark\": \"One Dark\""))
        // Surfaces step darker, not lighter, on a light background.
        #expect(Rgb(hex: EditorThemes.palette(light).surface)!.lab.l <= light.background.lab.l)
    }
}
