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

    @Test func zedKeepsAThemeYouPickedLater() throws {
        let home = TempDir()
        home.write(".config/zed/settings.json", "{\"theme\": {\"mode\": \"dark\", \"light\": \"One Light\", \"dark\": \"Tint\"}}")
        _ = EditorThemes.write(s, paths: .init(home: home.path))
        // Then the user switches to another theme.
        home.write(".config/zed/settings.json", "{\"theme\": {\"mode\": \"dark\", \"light\": \"One Light\", \"dark\": \"One Dark\"}}")
        let result = EditorThemes.write(s, paths: .init(home: home.path))

        #expect(home.read(".config/zed/settings.json").contains("\"dark\": \"One Dark\""))
        #expect(result.written == [home.file(".config/zed/themes/tint.json")])
    }

    @Test func vscodeSettingsGetNoColours() throws {
        let home = TempDir()
        let original = "{\"editor.fontSize\": 14}"
        home.write("Library/Application Support/Code/User/settings.json", original)
        home.write(".vscode/extensions/extensions.json", "[]")
        _ = EditorThemes.write(s, paths: .init(home: home.path))

        let settings = try json(home.file("Library/Application Support/Code/User/settings.json"))
        #expect(settings["editor.fontSize"] as? Int == 14)
        #expect(settings["workbench.colorTheme"] as? String == "Tint")
        // Colours there would paint every other theme too.
        #expect(settings["workbench.colorCustomizations"] == nil)
        #expect(settings["editor.tokenColorCustomizations"] == nil)
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

        // Applying again leaves the settings as they are.
        _ = EditorThemes.write(s, paths: .init(home: home.path))
        #expect(home.read("Library/Application Support/Code/User/settings.json") == text)
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

    @Test func geminiKeepsAThemeYouPickedLater() throws {
        let home = TempDir()
        home.write(".gemini/settings.json", "{}")
        _ = EditorThemes.write(s, paths: .init(home: home.path))
        var settings = try json(home.file(".gemini/settings.json"))
        var ui = settings["ui"] as! [String: Any]
        ui["theme"] = "Dracula"
        settings["ui"] = ui
        home.write(".gemini/settings.json", String(decoding: try JSONSerialization.data(withJSONObject: settings), as: UTF8.self))
        _ = EditorThemes.write(s, paths: .init(home: home.path))

        let after = try json(home.file(".gemini/settings.json"))["ui"] as! [String: Any]
        #expect(after["theme"] as? String == "Dracula")
        #expect((after["customThemes"] as! [String: Any])["Tint"] != nil)
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
    let settingsFile = "Library/Application Support/Code/User/settings.json"
    let folder = ".vscode/extensions/duma799.tint-theme-1.1.0"

    func json(_ home: TempDir, _ name: String) throws -> Any {
        try JSONSerialization.jsonObject(with: FileManager.default.contents(atPath: home.file(name))!)
    }

    @Test func vscodeGetsASelectableTintThemeExtensionThatItWatches() throws {
        let home = TempDir()
        home.write(settingsFile, "{\"editor.fontSize\": 14}")
        home.write(".vscode/extensions/extensions.json", "[{\"identifier\": {\"id\": \"ms-python.python\"}, \"version\": \"1.0.0\"}]")
        _ = EditorThemes.write(s, paths: .init(home: home.path))

        let manifest = try json(home, folder + "/package.json") as! [String: Any]
        let themes = (manifest["contributes"] as! [String: Any])["themes"] as! [[String: Any]]
        #expect(themes[0]["label"] as? String == "Tint")
        #expect(themes[0]["uiTheme"] as? String == "vs-dark")
        // VS Code re-reads a watched theme file as soon as it changes.
        #expect(themes[0]["_watch"] as? Bool == true)

        let theme = try json(home, folder + "/themes/tint-color-theme.json") as! [String: Any]
        #expect((theme["colors"] as! [String: String])["terminal.ansiBlue"] == s[4].hex)
        #expect(!(theme["tokenColors"] as! [Any]).isEmpty)

        let settings = try json(home, settingsFile) as! [String: Any]
        #expect(settings["workbench.colorTheme"] as? String == "Tint")
        #expect(settings["editor.fontSize"] as? Int == 14)

        // Registered once, next to the existing extensions; a second apply doesn't add it again.
        _ = EditorThemes.write(s, paths: .init(home: home.path))
        let registry = try json(home, ".vscode/extensions/extensions.json") as! [[String: Any]]
        let ids = registry.compactMap { ($0["identifier"] as? [String: Any])?["id"] as? String }
        #expect(ids == ["ms-python.python", "duma799.tint-theme"])
    }

    @Test func aThemeYouPickedStaysPicked() throws {
        let home = TempDir()
        home.write(settingsFile, "{}")
        home.write(".vscode/extensions/extensions.json", "[]")
        _ = EditorThemes.write(s, paths: .init(home: home.path))
        home.write(settingsFile, "{\"workbench.colorTheme\": \"Tokyo Night\"}")
        let result = EditorThemes.write(s, paths: .init(home: home.path))

        #expect(home.read(settingsFile) == "{\"workbench.colorTheme\": \"Tokyo Night\"}")
        #expect(!result.written.contains(home.file(settingsFile)))
    }

    @Test func anOlderVersionOfTheThemeIsReplaced() throws {
        let home = TempDir()
        home.write(settingsFile, "{\"workbench.colorTheme\": \"Tokyo Night\"}")
        let old = home.write(".vscode/extensions/duma799.tint-theme-1.0.0/package.json", "{}")
        home.write(".vscode/extensions/extensions.json", """
        [{"identifier": {"id": "duma799.tint-theme"}, "version": "1.0.0", "relativeLocation": "duma799.tint-theme-1.0.0"},
         {"identifier": {"id": "ms-python.python"}, "version": "1.0.0"}]
        """)
        _ = EditorThemes.write(s, paths: .init(home: home.path))

        #expect(!TintPaths.exists(old))
        #expect(TintPaths.exists(home.file(folder + "/package.json")))
        let registry = try json(home, ".vscode/extensions/extensions.json") as! [[String: Any]]
        #expect(registry.compactMap { ($0["identifier"] as? [String: Any])?["id"] as? String } == ["duma799.tint-theme", "ms-python.python"])
        #expect(registry[0]["version"] as? String == "1.1.0")
        #expect(registry[0]["relativeLocation"] as? String == "duma799.tint-theme-1.1.0")
        // Not a first install: the user's own pick stays.
        #expect((try json(home, settingsFile) as! [String: Any])["workbench.colorTheme"] as? String == "Tokyo Night")
    }

    @Test func coloursOlderVersionsLeftInTheSettingsAreRemoved() throws {
        let home = TempDir()
        // tint 0.7.0's colours over every theme, a "[Tint]" section, and the user's own.
        var workbench: [String: Any] = EditorThemes.vscodeColors(s).filter { !$0.key.hasPrefix("charts.") }
        workbench["[Tint]"] = ["editor.background": "#010102"]
        workbench["[One Dark Pro]"] = ["editor.background": "#282c34"]
        workbench["statusBarItem.compactHoverBackground"] = "#123456"
        let tokens: [String: Any] = [
            "comments": ["foreground": "#888888"], "keywords": ["fontStyle": "bold"], "functions": [:],
            "variables": [:], "strings": [:], "types": [:], "numbers": [:], "textMateRules": [],
            "[Tint]": ["comments": "#606063"],
            "[One Dark Pro]": ["comments": "#5c6370"],
        ]
        let settings: [String: Any] = ["workbench.colorCustomizations": workbench, "editor.tokenColorCustomizations": tokens, "editor.fontSize": 14]
        home.write(settingsFile, String(decoding: try JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted), as: UTF8.self))
        _ = EditorThemes.write(s, paths: .init(home: home.path))

        let after = try json(home, settingsFile) as! [String: Any]
        let keptWorkbench = after["workbench.colorCustomizations"] as! [String: Any]
        #expect(Set(keptWorkbench.keys) == ["[One Dark Pro]", "statusBarItem.compactHoverBackground"])
        #expect(Set((after["editor.tokenColorCustomizations"] as! [String: Any]).keys) == ["[One Dark Pro]"])
        #expect(after["editor.fontSize"] as? Int == 14)
    }

    @Test func emptiedCustomizationsGoAwayAndCommentsStay() throws {
        let home = TempDir()
        home.write(settingsFile, """
        {
            // Font
            "editor.fontSize": 14,
            "workbench.colorCustomizations": {
                "[Tint]": { "editor.background": "#010102" }
            },
            "editor.tokenColorCustomizations": {
                "[Tint]": { "comments": { "fontStyle": "italic", } }
            }
        }
        """)
        _ = EditorThemes.write(s, paths: .init(home: home.path))

        let text = home.read(settingsFile)
        #expect(text.contains("// Font"))
        #expect(!text.contains("Customizations"))
        #expect((JSONCEditor.parse(text) as? [String: Any])?["editor.fontSize"] as? Int == 14)
    }

    @Test func aFewColoursOfYourOwnAreNotMistakenForTints() throws {
        let home = TempDir()
        let original = "{\"workbench.colorCustomizations\": {\"editor.background\": \"#000000\", \"terminal.ansiBlue\": \"#0000ff\"}}"
        home.write(settingsFile, original)
        _ = EditorThemes.write(s, paths: .init(home: home.path))
        #expect(home.read(settingsFile) == original)
    }

    @Test func theEditorTakesTheSchemesBackgroundAndItsPanelsKeepItsColour() {
        let workbench = EditorThemes.vscodeColors(s)
        #expect(workbench["editor.background"] == s.background.hex)
        #expect(workbench["terminal.background"] == s.background.hex)
        let background = s.background.lab
        for key in ["sideBar.background", "tab.inactiveBackground", "panel.background", "editor.lineHighlightBackground"] {
            let panel = Rgb(hex: workbench[key]!)!.lab
            #expect(panel.l > background.l, "\(key) is lighter on a dark theme")
            #expect(abs(panel.hue - background.hue) < 15, "\(key) keeps the background's hue")
        }
    }

    @Test(arguments: ThemeMode.allCases)
    func everyColourIsAHexColour(mode: ThemeMode) throws {
        let scheme = try SchemeBuilder.build(SchemeTests.night, mode: mode)
        let hex = try Regex("^#[0-9a-f]{6}([0-9a-f]{2})?$")
        for (key, value) in EditorThemes.vscodeColors(scheme) {
            #expect(value.wholeMatch(of: hex) != nil, "\(key): \(value)")
        }
    }

    @Test func withoutAnExtensionsFolderNothingChanges() throws {
        let home = TempDir()
        home.write(settingsFile, "{}")
        let result = EditorThemes.write(s, paths: .init(home: home.path))
        #expect(result.written.isEmpty)
        #expect(home.read(settingsFile) == "{}")
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

    @Test(arguments: [
        ("{\n    \"a\": 1,\n    \"b\": 2,\n    \"c\": 3\n}", "b"),
        ("{\n    \"a\": 1,\n    \"b\": 2\n}", "b"),
        ("{\n    \"b\": {\"x\": [1, {\"y\": 2}]}, // about b\n    \"a\": 1\n}", "b"),
        ("{\"a\": 1, \"b\": 2}", "a"),
        ("{\"b\": 2}", "b"),
        ("{\n    // keep\n    \"a\": 1, /* keep too */\n    \"b\": \"}\",\n}", "b"),
    ])
    func removesAKeyAndNothingElse(text: String, key: String) throws {
        var e = JSONCEditor(text)
        try e.remove(key)
        var expected = JSONCEditor.parse(text) as! [String: Any]
        expected.removeValue(forKey: key)
        #expect(try JSONCEditor.canonical(JSONCEditor.parse(e.text)!) == JSONCEditor.canonical(expected), "\(e.text)")
        #expect(!e.text.contains("\"\(key)\""))
        if text.contains("// keep") { #expect(e.text.contains("// keep") && e.text.contains("/* keep too */")) }
    }

    @Test func removingAMissingKeyChangesNothing() throws {
        var e = JSONCEditor("{\"a\": 1}")
        try e.remove("b")
        #expect(e.text == "{\"a\": 1}")
    }

    @Test func windowsLineEndingsAreReadAndEdited() throws {
        let text = "{\r\n    // a comment\r\n    \"a\": 1,\r\n    \"b\": 2\r\n}\r\n"
        #expect((JSONCEditor.parse(text) as? [String: Any])?["b"] as? Int == 2)
        var e = JSONCEditor(text)
        try e.set("a", 5)
        try e.remove("b")
        let parsed = JSONCEditor.parse(e.text) as! [String: Any]
        #expect(parsed.count == 1 && parsed["a"] as? Int == 5)
        #expect(e.text.contains("// a comment"))
    }
}
