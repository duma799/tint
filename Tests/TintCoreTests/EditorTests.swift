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

    @Test func settingsWithCommentsAreEditedAndKeepTheirComments() throws {
        let home = TempDir()
        home.write("Library/Application Support/Code/User/settings.json", """
        {
            // Шрифт + лигатуры
            "editor.fontSize": 14,
            /* keep me */
            "workbench.colorTheme": "Tokyo Night",
            "files.autoSave": "afterDelay", // trailing comment
        }
        """)
        home.write(".vscode/extensions/extensions.json", "[]")
        let result = EditorThemes.write(s, paths: .init(home: home.path))
        #expect(result.warnings.isEmpty, "\(result.warnings)")

        let text = home.read("Library/Application Support/Code/User/settings.json")
        #expect(text.contains("// Шрифт + лигатуры"))
        #expect(text.contains("/* keep me */"))
        #expect(text.contains("// trailing comment"))
        #expect(text.contains("\"workbench.colorTheme\": \"Tint\""))
        #expect(!text.contains("Tokyo Night"))
        let parsed = JSONCEditor.parse(text) as! [String: Any]
        #expect(parsed["editor.fontSize"] as? Int == 14)
        #expect((parsed["workbench.colorCustomizations"] as? [String: String])?["terminal.ansiBlue"] == s[4].hex)

        // Applying again replaces tint's keys instead of adding them twice.
        _ = EditorThemes.write(s, paths: .init(home: home.path))
        let again = home.read("Library/Application Support/Code/User/settings.json")
        #expect(again.components(separatedBy: "workbench.colorCustomizations").count == 2)
        #expect(again.contains("// Шрифт + лигатуры"))
    }

    @Test func brokenSettingsAreLeftAloneWithAWarning() {
        let home = TempDir()
        let original = "{ \"editor.fontSize\": 14,,, oops"
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

struct VSCodeThemeTests {
    let s = testScheme

    @Test func vscodeGetsASelectableTintThemeExtension() throws {
        let home = TempDir()
        home.write("Library/Application Support/Code/User/settings.json", "{\"editor.fontSize\": 14}")
        home.write(".vscode/extensions/extensions.json", "[{\"identifier\": {\"id\": \"ms-python.python\"}, \"version\": \"1.0.0\"}]")
        _ = EditorThemes.write(s, paths: .init(home: home.path))

        let folder = ".vscode/extensions/duma799.tint-theme-1.0.0"
        let manifest = try JSONSerialization.jsonObject(with: FileManager.default.contents(atPath: home.file(folder + "/package.json"))!) as! [String: Any]
        let themes = (manifest["contributes"] as! [String: Any])["themes"] as! [[String: Any]]
        #expect(themes[0]["label"] as? String == "Tint")
        #expect(themes[0]["uiTheme"] as? String == "vs-dark")

        let theme = try JSONSerialization.jsonObject(with: FileManager.default.contents(atPath: home.file(folder + "/themes/tint-color-theme.json"))!) as! [String: Any]
        #expect((theme["colors"] as! [String: String])["terminal.ansiBlue"] == s[4].hex)
        #expect(!(theme["tokenColors"] as! [Any]).isEmpty)

        let settings = try JSONSerialization.jsonObject(with: FileManager.default.contents(atPath: home.file("Library/Application Support/Code/User/settings.json"))!) as! [String: Any]
        #expect(settings["workbench.colorTheme"] as? String == "Tint")
        #expect(settings["editor.fontSize"] as? Int == 14)

        // Registered once, next to the existing extensions; a second apply doesn't add it again.
        _ = EditorThemes.write(s, paths: .init(home: home.path))
        let registry = try JSONSerialization.jsonObject(with: FileManager.default.contents(atPath: home.file(".vscode/extensions/extensions.json"))!) as! [[String: Any]]
        let ids = registry.compactMap { ($0["identifier"] as? [String: Any])?["id"] as? String }
        #expect(ids == ["ms-python.python", "duma799.tint-theme"])
    }

    @Test func withoutAnExtensionsFolderOnlyTheSettingsChange() throws {
        let home = TempDir()
        home.write("Library/Application Support/Code/User/settings.json", "{}")
        let result = EditorThemes.write(s, paths: .init(home: home.path))
        #expect(result.written == [home.file("Library/Application Support/Code/User/settings.json")])
    }
}

struct JSONCEditorTests {
    @Test func addsAKeyToAnEmptyObject() throws {
        var e = JSONCEditor("{}\n")
        try e.set("a", 1)
        #expect((JSONCEditor.parse(e.text) as? [String: Any])?["a"] as? Int == 1)
    }

    @Test func addsAfterTheLastEntryWithACommaAndKeepsComments() throws {
        var e = JSONCEditor("{\n    // hi\n    \"x\": true // after\n}\n")
        try e.set("y", ["k": "v"])
        #expect(e.text.contains("// hi"))
        #expect(e.text.contains("// after"))
        let parsed = JSONCEditor.parse(e.text) as! [String: Any]
        #expect(parsed["x"] as? Bool == true)
        #expect((parsed["y"] as? [String: String])?["k"] == "v")
    }

    @Test func replacesOnlyTheTopLevelKey() throws {
        var e = JSONCEditor("{\"a\": {\"theme\": 1}, \"theme\": \"old\", \"s\": \"a // not a comment\"}")
        try e.set("theme", "new")
        let parsed = JSONCEditor.parse(e.text) as! [String: Any]
        #expect(parsed["theme"] as? String == "new")
        #expect((parsed["a"] as? [String: Int])?["theme"] == 1)
        #expect(parsed["s"] as? String == "a // not a comment")
    }

    @Test func replacesAnObjectValueWithNestedBracesAndComments() throws {
        var e = JSONCEditor("{\n  \"c\": {\n    \"x\": { \"y\": [1, 2] }, // }\n  },\n  \"z\": 3\n}")
        try e.set("c", ["new": true])
        let parsed = JSONCEditor.parse(e.text) as! [String: Any]
        #expect((parsed["c"] as? [String: Bool])?["new"] == true)
        #expect(parsed["z"] as? Int == 3)
    }
}
