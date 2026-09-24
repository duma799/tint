import Foundation

/// Editor themes made from the scheme: Zed, VS Code, Antigravity (a VS Code
/// fork) and Gemini CLI. Each is written only if that app's config folder
/// exists; editors re-read these files by themselves.
public enum EditorThemes {
    /// Where each editor keeps its settings, relative to a home folder (so
    /// tests can use a temporary one).
    public struct Paths: Sendable {
        public var home: String

        public init(home: String = TintPaths.home) { self.home = home }

        var zed: String { home + "/.config/zed" }
        var vscode: String { home + "/Library/Application Support/Code/User" }
        var antigravity: String { home + "/Library/Application Support/Antigravity/User" }
        var gemini: String { home + "/.gemini" }
    }

    public struct Result: Sendable {
        public var written: [String] = []
        public var warnings: [String] = []
    }

    public static let themeName = "Tint"

    public static func write(_ scheme: Scheme, paths: Paths = Paths()) -> Result {
        var result = Result()
        func attempt(_ name: String, _ body: () throws -> [String]) {
            do {
                result.written += try body()
            } catch {
                result.warnings.append("\(name): \(error)")
            }
        }
        attempt("Zed") { try zed(scheme, folder: paths.zed) }
        attempt("VS Code") { try vscode(scheme, folder: paths.vscode) }
        attempt("Antigravity") { try vscode(scheme, folder: paths.antigravity) }
        attempt("Gemini CLI") { try gemini(scheme, folder: paths.gemini) }
        return result
    }

    enum Failure: Error, CustomStringConvertible {
        case notJSON(String)

        var description: String {
            switch self {
            case .notJSON(let path): "\(path) isn't plain JSON (comments?), so tint left it alone"
            }
        }
    }

    // MARK: Zed

    /// `~/.config/zed/themes/tint.json`, and the settings' theme for this
    /// scheme's mode pointed at it.
    static func zed(_ scheme: Scheme, folder: String) throws -> [String] {
        guard TintPaths.isDirectory(folder) else { return [] }
        let themes = folder + "/themes"
        try FileManager.default.createDirectory(atPath: themes, withIntermediateDirectories: true)
        let path = themes + "/tint.json"
        try writeJSON(zedTheme(scheme), to: path)
        var written = [path]

        // Point `"theme": { … "dark": "…" }` (or "light") at Tint, touching nothing else.
        let settings = folder + "/settings.json"
        if var text = try? String(contentsOfFile: settings, encoding: .utf8) {
            let key = scheme.mode == .dark ? "dark" : "light"
            let pattern = #"("theme"\s*:\s*\{[^}]*""# + key + #""\s*:\s*")[^"]*(")"#
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(text.startIndex..., in: text)
                let updated = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "$1\(themeName)$2")
                if updated != text {
                    text = updated
                    try PywalWriter.atomicWrite(text, to: settings)
                    written.append(settings)
                }
            }
        }
        return written
    }

    static func zedTheme(_ s: Scheme) -> [String: Any] {
        let c = palette(s)
        let style: [String: Any] = [
            "border": c.surface, "border.variant": c.elevated, "border.focused": c.accent, "border.selected": c.accent,
            "border.transparent": "#00000000", "border.disabled": c.surface,
            "elevated_surface.background": c.elevated, "surface.background": c.surface, "background": c.bg,
            "element.background": c.surface, "element.hover": c.selection, "element.active": c.selection,
            "element.selected": c.selection, "element.disabled": c.bg, "drop_target.background": c.selection + "cc",
            "ghost_element.background": "#00000000", "ghost_element.hover": c.selection, "ghost_element.active": c.selection,
            "ghost_element.selected": c.selection, "ghost_element.disabled": c.bg,
            "text": c.label, "text.muted": c.muted, "text.placeholder": c.muted, "text.disabled": c.muted, "text.accent": c.accent,
            "icon": c.icon, "icon.muted": c.muted, "icon.disabled": c.muted, "icon.placeholder": c.muted, "icon.accent": c.accent,
            "status_bar.background": c.surface, "title_bar.background": c.bg, "toolbar.background": c.surface,
            "tab_bar.background": c.surface, "tab.inactive_background": c.surface, "tab.active_background": c.bg,
            "search.match_background": c.selection, "panel.background": c.elevated, "panel.focused_border": c.accent,
            "pane.focused_border": c.accent, "scrollbar.thumb.background": c.selection + "80",
            "scrollbar.thumb.hover_background": c.selection + "cc", "scrollbar.thumb.border": "#00000000",
            "scrollbar.track.background": "#00000000", "scrollbar.track.border": "#00000000",
            "editor.foreground": c.label, "editor.background": c.bg, "editor.gutter.background": c.bg,
            "editor.subheader.background": c.surface, "editor.active_line.background": c.active,
            "editor.highlighted_line.background": c.active, "editor.line_number": c.muted,
            "editor.active_line_number": c.label, "editor.invisible": c.muted, "editor.wrap_guide": c.bg,
            "editor.active_wrap_guide": c.bg, "editor.document_highlight.read_background": c.selection + "80",
            "editor.document_highlight.write_background": c.selection + "80",
            "terminal.background": c.bg, "terminal.foreground": s.foreground.hex,
            "terminal.ansi.black": s[0].hex, "terminal.ansi.red": s[1].hex, "terminal.ansi.green": s[2].hex,
            "terminal.ansi.yellow": s[3].hex, "terminal.ansi.blue": s[4].hex, "terminal.ansi.magenta": s[5].hex,
            "terminal.ansi.cyan": s[6].hex, "terminal.ansi.white": s[7].hex,
            "terminal.ansi.bright_black": s[8].hex, "terminal.ansi.bright_red": s[9].hex,
            "terminal.ansi.bright_green": s[10].hex, "terminal.ansi.bright_yellow": s[11].hex,
            "terminal.ansi.bright_blue": s[12].hex, "terminal.ansi.bright_magenta": s[13].hex,
            "terminal.ansi.bright_cyan": s[14].hex, "terminal.ansi.bright_white": s[15].hex,
            "link_text.hover": c.accent,
            "conflict": c.accent, "conflict.background": c.bg, "conflict.border": c.accent,
            "created": c.string, "created.background": c.bg, "created.border": c.string,
            "deleted": c.accent, "deleted.background": c.bg, "deleted.border": c.accent,
            "error": c.accent, "error.background": c.bg, "error.border": c.accent,
            "hidden": c.muted, "hidden.background": c.bg, "hidden.border": c.muted,
            "hint": c.icon, "hint.background": c.bg, "hint.border": c.icon,
            "ignored": c.muted, "ignored.background": c.bg, "ignored.border": c.muted,
            "info": c.icon, "info.background": c.bg, "info.border": c.icon,
            "modified": c.function, "modified.background": c.bg, "modified.border": c.function,
            "predictive": c.muted, "predictive.background": c.bg, "predictive.border": c.muted,
            "renamed": c.string, "renamed.background": c.bg, "renamed.border": c.string,
            "success": c.string, "success.background": c.bg, "success.border": c.string,
            "unreachable": c.muted, "unreachable.background": c.bg, "unreachable.border": c.muted,
            "warning": c.function, "warning.background": c.bg, "warning.border": c.function,
            "players": [Any](),
            "syntax": [
                "attribute": ["color": c.attribute],
                "boolean": ["color": c.keywordLight, "font_weight": 700],
                "comment": ["color": c.comment, "font_style": "italic"],
                "comment.doc": ["color": c.commentDoc, "font_style": "italic"],
                "constant": ["color": c.keyword, "font_weight": 700],
                "constructor": ["color": c.functionLight, "font_weight": 700],
                "embedded": ["color": c.label],
                "emphasis": ["font_style": "italic"],
                "emphasis.strong": ["font_weight": 700],
                "enum": ["color": c.typeLight, "font_weight": 700],
                "function": ["color": c.function, "font_weight": 700],
                "hint": ["color": c.comment, "font_weight": 700],
                "keyword": ["color": c.keyword, "font_weight": 700],
                "label": ["color": c.label],
                "link_text": ["color": c.keywordLight, "font_style": "italic"],
                "link_uri": ["color": c.stringLight],
                "number": ["color": c.keywordDim],
                "operator": ["color": c.operatorColor],
                "predictive": ["color": c.comment, "font_style": "italic"],
                "preproc": ["color": c.keywordDim],
                "primary": ["color": c.label],
                "property": ["color": c.property],
                "punctuation": ["color": c.punctuation],
                "punctuation.bracket": ["color": c.bracket],
                "punctuation.delimiter": ["color": c.punctuation],
                "punctuation.list_marker": ["color": c.punctuation],
                "punctuation.special": ["color": c.comment],
                "string": ["color": c.string],
                "string.escape": ["color": c.stringDim],
                "string.regex": ["color": c.stringLight],
                "string.special": ["color": c.stringLight],
                "string.special.symbol": ["color": c.stringDim],
                "tag": ["color": c.type],
                "text.literal": ["color": c.string],
                "title": ["color": c.keywordLight, "font_weight": 700],
                "type": ["color": c.type, "font_weight": 700],
                "variable": ["color": c.label],
                "variable.special": ["color": c.variableSpecial, "font_style": "italic"],
                "variant": ["color": c.typeDim],
            ] as [String: Any],
        ]
        return [
            "$schema": "https://zed.dev/schema/themes/v0.2.0.json",
            "name": themeName,
            "author": "tint",
            "themes": [["name": themeName, "appearance": s.mode.rawValue, "style": style]],
        ]
    }

    // MARK: VS Code (and Antigravity)

    /// `workbench.colorCustomizations` and `editor.tokenColorCustomizations`
    /// in the user settings; every other setting is kept.
    static func vscode(_ scheme: Scheme, folder: String) throws -> [String] {
        let path = folder + "/settings.json"
        guard let data = FileManager.default.contents(atPath: path) else { return [] }
        guard var settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.notJSON(path)
        }
        let (workbench, tokens) = vscodeColors(scheme)
        settings["workbench.colorCustomizations"] = workbench
        settings["editor.tokenColorCustomizations"] = tokens
        try writeJSON(settings, to: path)
        return [path]
    }

    static func vscodeColors(_ s: Scheme) -> (workbench: [String: String], tokens: [String: Any]) {
        let c = palette(s)
        let dark = s.mode == .dark
        // Dark: a deeper background than the terminal's, for long editing sessions.
        let bg = dark ? RGBMath.darken(s.background, 0.88).hex : s.background.hex
        let elevated = dark ? RGBMath.darken(s.background, 0.83).hex : RGBMath.darken(s.background, 0.03).hex
        let surface = dark ? RGBMath.darken(s.background, 0.85).hex : RGBMath.darken(s.background, 0.02).hex
        let active = dark ? RGBMath.darken(s.background, 0.75).hex : RGBMath.darken(s.background, 0.05).hex
        let border = dark ? RGBMath.darken(s[1], 0.75).hex : RGBMath.lighten(s[1], 0.75).hex
        let selection = dark ? RGBMath.darken(s[1], 0.7).hex : RGBMath.lighten(s[1], 0.7).hex

        let workbench: [String: String] = [
            "editor.background": bg, "editor.foreground": c.label, "editorCursor.foreground": c.accent,
            "editorLineNumber.foreground": c.muted, "editorLineNumber.activeForeground": c.label,
            "editorGutter.background": bg, "editorGutter.addedBackground": c.string,
            "editorGutter.modifiedBackground": c.function, "editorGutter.deletedBackground": c.accent,
            "editor.lineHighlightBackground": active, "editor.lineHighlightBorder": active,
            "editor.selectionBackground": selection, "editor.inactiveSelectionBackground": surface,
            "activityBar.background": bg, "activityBar.foreground": c.icon, "activityBar.inactiveForeground": c.muted,
            "activityBar.border": border, "activityBarBadge.background": c.accent, "activityBarBadge.foreground": bg,
            "sideBar.background": elevated, "sideBar.foreground": c.label, "sideBar.border": border,
            "sideBarSectionHeader.background": elevated, "sideBarSectionHeader.foreground": c.label,
            "sideBarSectionHeader.border": border,
            "statusBar.background": bg, "statusBar.foreground": c.label, "statusBar.border": border,
            "titleBar.activeBackground": bg, "titleBar.activeForeground": c.label,
            "titleBar.inactiveBackground": bg, "titleBar.inactiveForeground": c.muted, "titleBar.border": border,
            "panel.background": elevated, "panel.border": border, "panelTitle.activeBorder": c.accent,
            "panelTitle.activeForeground": c.label, "panelTitle.inactiveForeground": c.muted,
            "editorHoverWidget.background": elevated, "editorHoverWidget.border": border,
            "editorSuggestWidget.background": elevated, "editorSuggestWidget.border": border,
            "editorSuggestWidget.selectedBackground": selection,
            "scrollbarSlider.background": selection + "80", "scrollbarSlider.hoverBackground": selection + "cc",
            "scrollbarSlider.activeBackground": selection + "cc", "focusBorder": c.accent,
            "tab.activeBackground": bg, "tab.activeForeground": c.label, "tab.inactiveBackground": surface,
            "tab.inactiveForeground": c.muted, "tab.activeBorder": c.accent, "tab.activeBorderTop": c.accent,
            "tab.border": border, "tab.hoverBackground": elevated, "tab.hoverForeground": c.label,
            "editorGroupHeader.tabsBackground": surface, "editorGroupHeader.tabsBorder": border,
            "breadcrumb.background": surface, "breadcrumb.foreground": c.muted,
            "breadcrumb.focusForeground": c.label, "breadcrumb.activeSelectionForeground": c.accent,
            "list.activeSelectionBackground": selection, "list.activeSelectionForeground": c.label,
            "list.inactiveSelectionBackground": surface, "list.inactiveSelectionForeground": c.label,
            "list.hoverBackground": active, "list.hoverForeground": c.label, "list.focusBackground": selection,
            "list.focusForeground": c.label, "list.highlightForeground": c.accent,
            "button.background": c.accent, "button.foreground": bg, "button.hoverBackground": c.function,
            "button.secondaryBackground": surface, "button.secondaryForeground": c.label,
            "button.secondaryHoverBackground": elevated,
            "input.background": bg, "input.foreground": c.label, "input.border": border,
            "input.placeholderForeground": c.muted, "inputOption.activeBackground": c.accent,
            "inputOption.activeForeground": bg,
            "dropdown.background": elevated, "dropdown.foreground": c.label, "dropdown.border": border,
            "notifications.background": elevated, "notifications.foreground": c.label, "notifications.border": border,
            "notificationCenter.border": border, "notificationCenterHeader.background": elevated,
            "notificationCenterHeader.foreground": c.label, "notificationToast.border": border,
            "notificationsErrorIcon.foreground": c.accent, "notificationsWarningIcon.foreground": c.function,
            "notificationsInfoIcon.foreground": c.icon,
            "quickInput.background": elevated, "quickInput.foreground": c.label,
            "quickInputList.focusBackground": selection, "quickInputList.focusForeground": c.label,
            "quickInputTitle.background": elevated,
            "badge.background": c.accent, "badge.foreground": bg, "progressBar.background": c.accent,
            "editorWidget.background": elevated, "editorWidget.border": border, "editorWidget.foreground": c.label,
            "widget.shadow": bg + "80", "settings.headerForeground": c.label, "settings.modifiedItemIndicator": c.accent,
            "welcomePage.background": bg, "walkThrough.embeddedEditorBackground": elevated,
            "terminal.background": bg, "terminal.foreground": s.foreground.hex,
            "terminal.ansiBlack": s[0].hex, "terminal.ansiRed": s[1].hex, "terminal.ansiGreen": s[2].hex,
            "terminal.ansiYellow": s[3].hex, "terminal.ansiBlue": s[4].hex, "terminal.ansiMagenta": s[5].hex,
            "terminal.ansiCyan": s[6].hex, "terminal.ansiWhite": s[7].hex,
            "terminal.ansiBrightBlack": s[8].hex, "terminal.ansiBrightRed": s[9].hex,
            "terminal.ansiBrightGreen": s[10].hex, "terminal.ansiBrightYellow": s[11].hex,
            "terminal.ansiBrightBlue": s[12].hex, "terminal.ansiBrightMagenta": s[13].hex,
            "terminal.ansiBrightCyan": s[14].hex, "terminal.ansiBrightWhite": s[15].hex,
            "terminalCursor.background": bg, "terminalCursor.foreground": c.accent,
        ]

        func rule(_ scope: Any, _ color: String, _ style: String? = nil) -> [String: Any] {
            var settings: [String: String] = ["foreground": color]
            if let style { settings["fontStyle"] = style }
            return ["scope": scope, "settings": settings]
        }
        let tokens: [String: Any] = [
            "comments": ["foreground": c.comment, "fontStyle": "italic"],
            "keywords": ["foreground": c.keyword, "fontStyle": "bold"],
            "functions": ["foreground": c.function, "fontStyle": "bold"],
            "variables": ["foreground": c.label],
            "strings": ["foreground": c.string],
            "types": ["foreground": c.type, "fontStyle": "bold"],
            "numbers": ["foreground": c.keywordDim],
            "textMateRules": [
                rule(["storage.type", "storage.modifier"], c.keyword, "bold"),
                rule(["entity.name.type", "entity.name.class"], c.type, "bold"),
                rule(["entity.name.type.interface", "entity.name.type.type-parameter"], c.typeLight, "bold"),
                rule("entity.name.type.enum", c.typeLight, "bold"),
                rule(["entity.name.function", "support.function"], c.function, "bold"),
                rule("entity.name.function.member", c.functionLight, "bold"),
                rule("entity.name.function.constructor", c.functionLight, "bold"),
                rule("variable.parameter", c.parameter, "italic"),
                rule("constant.language", c.keywordLight, "bold"),
                rule("constant.numeric", c.keywordDim),
                rule(["variable.other.property", "variable.other.object.property"], c.property),
                rule(["variable.language", "variable.language.this"], c.variableSpecial, "italic"),
                rule("punctuation.definition.string", c.stringDim),
                rule("constant.character.escape", c.stringDim),
                rule("string.regexp", c.stringLight),
                rule("string.template", c.string),
                rule("punctuation.definition.template-expression", c.keywordDim),
                rule(["punctuation.definition.variable", "punctuation.definition.parameters", "punctuation.definition.array"], c.punctuation),
                rule(["punctuation.separator", "punctuation.terminator"], c.punctuation),
                rule(["meta.brace", "punctuation.definition.block"], c.bracket),
                rule("keyword.operator", c.operatorColor),
                rule(["keyword.operator.comparison", "keyword.operator.assignment"], c.operatorColor),
                rule(["entity.name.function.decorator", "meta.decorator"], c.attribute),
                rule("entity.name.tag", c.type),
                rule("entity.other.attribute-name", c.attribute),
                rule(["comment.block.documentation", "comment.block.javadoc"], c.commentDoc, "italic"),
                rule(["keyword.control.import", "keyword.control.export"], c.keywordDim),
                rule("entity.name.type.module", c.string),
            ],
        ]
        return (workbench, tokens)
    }

    // MARK: Gemini CLI

    /// A "Tint" custom theme in `~/.gemini/settings.json`, selected.
    static func gemini(_ s: Scheme, folder: String) throws -> [String] {
        guard TintPaths.isDirectory(folder) else { return [] }
        let path = folder + "/settings.json"
        var settings: [String: Any] = [:]
        if let data = FileManager.default.contents(atPath: path) {
            guard let loaded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw Failure.notJSON(path)
            }
            settings = loaded
        }
        var ui = settings["ui"] as? [String: Any] ?? [:]
        var custom = ui["customThemes"] as? [String: Any] ?? [:]
        custom[themeName] = geminiTheme(s)
        ui["customThemes"] = custom
        ui["theme"] = themeName
        settings["ui"] = ui
        try writeJSON(settings, to: path)
        return [path]
    }

    static func geminiTheme(_ s: Scheme) -> [String: Any] {
        let c = palette(s)
        let fg = s.foreground.hex
        let added = RGBMath.darken(s[2], 0.6).hex, removed = RGBMath.darken(s[1], 0.6).hex
        return [
            "type": "custom", "name": themeName,
            "text": ["primary": fg, "secondary": c.muted, "link": c.icon, "accent": c.accent],
            "background": ["primary": c.bg, "diff": ["added": added, "removed": removed]],
            "border": ["default": c.surface, "focused": c.accent],
            "ui": ["comment": c.muted, "symbol": c.icon, "gradient": [c.accent, c.icon, c.label]],
            "status": ["error": s[1].hex, "success": s[2].hex, "warning": s[3].hex],
            "Background": c.bg, "Foreground": fg, "LightBlue": c.icon, "AccentBlue": c.icon,
            "AccentPurple": s[5].hex, "AccentCyan": s[6].hex, "AccentGreen": s[2].hex, "AccentYellow": s[3].hex,
            "AccentRed": s[1].hex, "DiffAdded": added, "DiffRemoved": removed, "Comment": c.muted, "Gray": c.muted,
            "DarkGray": RGBMath.darken(s[8], 0.3).hex, "GradientColors": [c.accent, c.icon, c.label],
        ]
    }

    // MARK: Shared

    /// The roles every editor theme uses, derived from the scheme the same way
    /// for all of them (and as the old reload-theme script did).
    struct Roles {
        var bg, surface, elevated, active, selection: String
        var accent, icon, label, muted: String
        var keyword, keywordLight, keywordDim: String
        var string, stringLight, stringDim: String
        var function, functionLight: String
        var type, typeLight, typeDim: String
        var punctuation, operatorColor, bracket, comment, commentDoc: String
        var variableSpecial, parameter, property, attribute: String
    }

    static func palette(_ s: Scheme) -> Roles {
        let dark = s.mode == .dark
        // Layers step away from the background: lighter on dark themes, darker on light.
        func layer(_ amount: Double) -> String {
            (dark ? RGBMath.lighten(s.background, amount) : RGBMath.darken(s.background, amount * 0.5)).hex
        }
        let label = s[6], c8 = s[8]
        return Roles(
            bg: s.background.hex, surface: layer(0.04), elevated: layer(0.08), active: layer(0.12), selection: layer(0.25),
            accent: s[1].hex, icon: s[4].hex, label: label.hex, muted: c8.hex,
            keyword: s[1].hex, keywordLight: RGBMath.lighten(s[1], 0.15).hex, keywordDim: RGBMath.darken(s[1], 0.2).hex,
            string: s[2].hex, stringLight: RGBMath.lighten(s[2], 0.2).hex, stringDim: RGBMath.darken(s[2], 0.15).hex,
            function: s[3].hex, functionLight: RGBMath.lighten(s[3], 0.15).hex,
            type: s[4].hex, typeLight: RGBMath.lighten(s[4], 0.15).hex, typeDim: RGBMath.darken(s[4], 0.2).hex,
            punctuation: RGBMath.blend(c8, label, 0.3).hex, operatorColor: RGBMath.blend(label, s[3], 0.25).hex,
            bracket: RGBMath.blend(c8, label, 0.5).hex, comment: c8.hex, commentDoc: RGBMath.lighten(c8, 0.15).hex,
            variableSpecial: RGBMath.blend(label, s[5], 0.3).hex, parameter: RGBMath.blend(label, s[4], 0.2).hex,
            property: RGBMath.blend(label, s[6], 0.4).hex, attribute: RGBMath.blend(s[4], s[6], 0.4).hex)
    }

    static func writeJSON(_ object: Any, to path: String) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try PywalWriter.atomicWrite(String(decoding: data, as: UTF8.self) + "\n", to: path)
    }
}

/// Simple per-channel sRGB mixing, as the editor themes have always used.
enum RGBMath {
    static func lighten(_ c: Rgb, _ amount: Double) -> Rgb {
        func f(_ v: UInt8) -> UInt8 { UInt8(min(255, Int(Double(v) + (255 - Double(v)) * amount))) }
        return Rgb(f(c.r), f(c.g), f(c.b))
    }

    static func darken(_ c: Rgb, _ amount: Double) -> Rgb {
        func f(_ v: UInt8) -> UInt8 { UInt8(max(0, Int(Double(v) * (1 - amount)))) }
        return Rgb(f(c.r), f(c.g), f(c.b))
    }

    static func blend(_ a: Rgb, _ b: Rgb, _ t: Double) -> Rgb {
        func f(_ x: UInt8, _ y: UInt8) -> UInt8 { UInt8(min(255, max(0, Int(Double(x) + (Double(y) - Double(x)) * t)))) }
        return Rgb(f(a.r, b.r), f(a.g, b.g), f(a.b, b.b))
    }
}
