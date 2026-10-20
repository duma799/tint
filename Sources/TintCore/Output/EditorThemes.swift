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
        var vscodeExtensions: String { home + "/.vscode/extensions" }
        var antigravityExtensions: String { home + "/.antigravity/extensions" }
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
        attempt("VS Code") { try vscode(scheme, folder: paths.vscode, extensions: paths.vscodeExtensions) }
        attempt("Antigravity") { try vscode(scheme, folder: paths.antigravity, extensions: paths.antigravityExtensions) }
        attempt("Gemini CLI") { try gemini(scheme, folder: paths.gemini) }
        return result
    }

    enum Failure: Error, CustomStringConvertible {
        case notJSON(String)

        var description: String {
            switch self {
            case .notJSON(let path): "\(path) isn't readable JSON, so tint left it alone"
            }
        }
    }

    // MARK: Zed

    /// `~/.config/zed/themes/tint.json`, and the settings' theme for this
    /// scheme's mode pointed at it — the first time, or while Tint is the
    /// theme anyway: once you pick another theme, it stays picked.
    static func zed(_ scheme: Scheme, folder: String) throws -> [String] {
        guard TintPaths.isDirectory(folder) else { return [] }
        let themes = folder + "/themes"
        try FileManager.default.createDirectory(atPath: themes, withIntermediateDirectories: true)
        let path = themes + "/tint.json"
        let firstTime = !TintPaths.exists(path)
        try writeJSON(zedTheme(scheme), to: path)
        var written = [path]

        // Point `"theme": { … "dark": "…" }` (or "light") at Tint, touching nothing else.
        let settings = folder + "/settings.json"
        if var text = try? String(contentsOfFile: settings, encoding: .utf8),
           firstTime || usesTint((JSONCEditor.parse(text) as? [String: Any])?["theme"]) {
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

    /// True if a Zed theme setting picks Tint: `"Tint"`, or `{ "dark": "Tint", … }`.
    static func usesTint(_ theme: Any?) -> Bool {
        if let name = theme as? String { return name == themeName }
        return (theme as? [String: Any])?.values.contains { $0 as? String == themeName } ?? false
    }

    static func zedTheme(_ s: Scheme) -> [String: Any] {
        let c = palette(s)
        let style: [String: Any] = [
            "border": c.border, "border.variant": c.elevated, "border.focused": c.accent, "border.selected": c.accent,
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

    /// A "Tint" colour theme, installed as a tiny local extension so it's in
    /// the theme picker. VS Code watches the theme file (`_watch` in its
    /// manifest) and re-reads it the moment tint rewrites it, so a new
    /// wallpaper re-colours the editor with no reload — and nothing goes in
    /// `workbench.colorCustomizations`, which would paint every other theme too.
    ///
    /// The theme is selected once, when it is first installed; after that the
    /// theme you pick stays. The colours tint 0.6–0.7 put in the user settings
    /// are removed; every other setting, and the file's comments, stay.
    static func vscode(_ scheme: Scheme, folder: String, extensions: String) throws -> [String] {
        let path = folder + "/settings.json"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        guard let settings = JSONCEditor.parse(text) as? [String: Any] else { throw Failure.notJSON(path) }

        // Edited in place, key by key: the user's comments and layout stay.
        var editor = JSONCEditor(text)
        var written: [String] = []
        if TintPaths.isDirectory(extensions) {
            let installed = try vscodeExtension(scheme, extensions: extensions)
            written += installed.written
            if installed.firstTime, settings["workbench.colorTheme"] as? String != themeName {
                try editor.set("workbench.colorTheme", themeName)
            }
        }

        // Recognised by how many of tint's keys they have: dozens of its
        // colour keys, or all its token shorthands — nobody writes that many by hand.
        for (key, ours, atLeast) in [
            ("workbench.colorCustomizations", Set(vscodeColors(anyScheme).keys), 50),
            ("editor.tokenColorCustomizations", legacyTokenKeys, legacyTokenKeys.count - 1),
        ] {
            guard let customizations = settings[key] as? [String: Any] else { continue }
            let kept = withoutTintColours(customizations, ours: ours, atLeast: atLeast)
            guard kept.count != customizations.count else { continue }
            if kept.isEmpty {
                try editor.remove(key)
            } else {
                try editor.set(key, kept)
            }
        }

        guard editor.text != text else { return written }
        try PywalWriter.atomicWrite(editor.text, to: path)
        return written + [path]
    }

    /// A customizations object without the colours tint put there: its
    /// `"[Tint]"` section, and the unscoped copy of its keys (`ours`) tint
    /// 0.6–0.7 wrote over every theme, if there are `atLeast` of them. Other
    /// themes' sections and the user's own keys stay.
    static func withoutTintColours(_ customizations: [String: Any], ours: Set<String>, atLeast: Int) -> [String: Any] {
        var kept = customizations
        kept.removeValue(forKey: "[\(themeName)]")
        let leftovers = kept.keys.filter(ours.contains)
        if leftovers.count >= atLeast {
            for key in leftovers { kept.removeValue(forKey: key) }
        }
        return kept
    }

    /// The token shorthands tint 0.6–0.7 wrote in `editor.tokenColorCustomizations`.
    static let legacyTokenKeys: Set<String> = ["comments", "keywords", "functions", "variables", "strings", "types", "numbers", "textMateRules"]

    /// Any scheme will do for listing the keys: they don't depend on the colours.
    private static let anyScheme = Scheme(
        background: Rgb(0, 0, 0), foreground: Rgb(255, 255, 255), cursor: Rgb(255, 255, 255),
        colors: [Rgb](repeating: Rgb(128, 128, 128), count: 16), mode: .dark)

    static let extensionID = "duma799.tint-theme"
    /// Bumped when the manifest changes: VS Code reads a manifest only when it
    /// sees a new version in extensions.json (1.1.0 added `_watch`).
    static let extensionVersion = "1.1.0"

    /// `<extensions>/duma799.tint-theme-<version>/`: a package.json that
    /// contributes the theme, and the theme itself. Also listed in the
    /// editor's extensions.json, which newer versions read to know what's
    /// installed; older versions of it are removed.
    /// - Returns: the files written, and whether the theme is new (no version of it was installed).
    static func vscodeExtension(_ scheme: Scheme, extensions: String) throws -> (written: [String], firstTime: Bool) {
        let fm = FileManager.default
        let folderName = "\(extensionID)-\(extensionVersion)"
        let folder = extensions + "/" + folderName
        let older = ((try? fm.contentsOfDirectory(atPath: extensions)) ?? [])
            .filter { $0.hasPrefix(extensionID + "-") && $0 != folderName }
        let firstTime = older.isEmpty && !TintPaths.exists(folder)
        try fm.createDirectory(atPath: folder + "/themes", withIntermediateDirectories: true)

        let dark = scheme.mode == .dark
        let manifest: [String: Any] = [
            "name": "tint-theme",
            "displayName": "Tint",
            "description": "Colours from your wallpaper, written by tint (github.com/duma799/tint).",
            "publisher": "duma799",
            "version": extensionVersion,
            "engines": ["vscode": "^1.60.0"],
            "categories": ["Themes"],
            "contributes": ["themes": [[
                "label": themeName, "uiTheme": dark ? "vs-dark" : "vs", "path": "./themes/tint-color-theme.json",
                // Re-read the theme whenever its file changes.
                "_watch": true,
            ] as [String: Any]]],
        ]
        let manifestPath = folder + "/package.json"
        let manifestChanged = try jsonText(manifest) != (try? String(contentsOfFile: manifestPath, encoding: .utf8))
        if manifestChanged { try writeJSON(manifest, to: manifestPath) }
        try writeJSON(vscodeTheme(scheme), to: folder + "/themes/tint-color-theme.json")
        var written = [folder + "/themes/tint-color-theme.json"]
        if manifestChanged { written.append(manifestPath) }

        // Register this version, the way VS Code records extensions it
        // installed, in place of any older one.
        let registry = extensions + "/extensions.json"
        if let data = fm.contents(atPath: registry),
           let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            let entry: [String: Any] = [
                "identifier": ["id": extensionID],
                "version": extensionVersion,
                "location": ["$mid": 1, "path": folder, "scheme": "file"],
                "relativeLocation": folderName,
            ]
            func isTint(_ e: [String: Any]) -> Bool { ((e["identifier"] as? [String: Any])?["id"] as? String) == extensionID }
            let current = entries.contains { isTint($0) && $0["version"] as? String == extensionVersion && $0["relativeLocation"] as? String == folderName }
            if !current {
                var updated = entries
                if let index = updated.firstIndex(where: isTint) {
                    updated[index] = entry
                    updated.removeAll { isTint($0) && ($0["version"] as? String) != extensionVersion }
                } else {
                    updated.append(entry)
                }
                try writeJSON(updated, to: registry)
                written.append(registry)
            }
        }

        // Only after the registry points at the new version.
        for name in older { try? fm.removeItem(atPath: extensions + "/" + name) }
        return (written, firstTime)
    }

    /// The colour theme file: the workbench colours, and token colours as TextMate rules.
    static func vscodeTheme(_ s: Scheme) -> [String: Any] {
        [
            "name": themeName,
            "type": s.mode.rawValue,
            "colors": vscodeColors(s),
            "tokenColors": vscodeTokenRules(s),
            "semanticHighlighting": true,
        ]
    }

    static func vscodeColors(_ s: Scheme) -> [String: String] {
        let c = palette(s)
        // The scheme's own background, the terminal's too: the editor takes
        // the wallpaper's colour, and its panels are shades of it.
        let bg = c.bg, elevated = c.elevated, surface = c.surface, active = c.active
        let border = c.border, selection = c.selection
        let red = s[1].hex, green = s[2].hex, yellow = s[3].hex, blue = s[4].hex, magenta = s[5].hex, cyan = s[6].hex

        return [
            // Everywhere
            "foreground": c.label, "descriptionForeground": c.muted, "disabledForeground": c.muted,
            "errorForeground": red, "icon.foreground": c.icon, "focusBorder": c.accent, "selection.background": selection,
            "widget.shadow": bg + "80", "scrollbar.shadow": bg + "80", "sash.hoverBorder": c.accent,
            "window.activeBorder": border, "window.inactiveBorder": border,
            "textLink.foreground": c.icon, "textLink.activeForeground": c.accent, "textPreformat.foreground": c.string,
            "textPreformat.background": surface, "textBlockQuote.background": surface, "textBlockQuote.border": border,
            "textCodeBlock.background": surface, "textSeparator.foreground": border,
            "toolbar.hoverBackground": active, "toolbar.activeBackground": selection,

            // Editor
            "editor.background": bg, "editor.foreground": c.label, "editorCursor.foreground": c.accent,
            "editorCursor.background": bg,
            "editorLineNumber.foreground": c.muted, "editorLineNumber.activeForeground": c.label,
            "editorGutter.background": bg, "editorGutter.addedBackground": c.string,
            "editorGutter.modifiedBackground": c.function, "editorGutter.deletedBackground": c.accent,
            "editorGutter.foldingControlForeground": c.muted, "editorGutter.commentRangeForeground": c.muted,
            "editor.lineHighlightBackground": active, "editor.lineHighlightBorder": active,
            "editor.selectionBackground": selection, "editor.inactiveSelectionBackground": surface,
            "editor.selectionHighlightBackground": selection + "80", "editor.wordHighlightBackground": selection + "80",
            "editor.wordHighlightStrongBackground": selection + "cc", "editor.wordHighlightTextBackground": selection + "80",
            "editor.findMatchBackground": selection, "editor.findMatchBorder": c.accent,
            "editor.findMatchHighlightBackground": selection + "80", "editor.findRangeHighlightBackground": surface,
            "editor.rangeHighlightBackground": surface, "editor.hoverHighlightBackground": active,
            "editor.linkedEditingBackground": selection + "80", "editor.foldBackground": surface,
            "editorLink.activeForeground": c.accent, "editorGhostText.foreground": c.muted,
            "editorWhitespace.foreground": border, "editorRuler.foreground": border, "editorCodeLens.foreground": c.muted,
            "editorIndentGuide.background1": border, "editorIndentGuide.activeBackground1": c.muted,
            "editorBracketMatch.background": selection + "80", "editorBracketMatch.border": c.muted,
            "editorBracketHighlight.foreground1": yellow, "editorBracketHighlight.foreground2": magenta,
            "editorBracketHighlight.foreground3": blue, "editorBracketHighlight.foreground4": green,
            "editorBracketHighlight.foreground5": cyan, "editorBracketHighlight.foreground6": red,
            "editorBracketHighlight.unexpectedBracket.foreground": red,
            "editorError.foreground": red, "editorWarning.foreground": yellow, "editorInfo.foreground": blue,
            "editorHint.foreground": cyan, "problemsErrorIcon.foreground": red, "problemsWarningIcon.foreground": yellow,
            "problemsInfoIcon.foreground": blue,
            "editorInlayHint.background": surface, "editorInlayHint.foreground": c.muted,
            "editorStickyScroll.background": elevated, "editorStickyScrollHover.background": active,
            "editorStickyScroll.border": border, "editorStickyScroll.shadow": bg + "80",
            "editorOverviewRuler.border": bg, "editorOverviewRuler.findMatchForeground": c.accent,
            "editorOverviewRuler.addedForeground": c.string, "editorOverviewRuler.modifiedForeground": c.function,
            "editorOverviewRuler.deletedForeground": c.accent, "editorOverviewRuler.errorForeground": red,
            "editorOverviewRuler.warningForeground": yellow, "editorOverviewRuler.infoForeground": blue,
            "editorPane.background": bg, "editorGroup.border": border, "editorGroup.dropBackground": selection + "80",
            "editorGroupHeader.tabsBackground": surface, "editorGroupHeader.tabsBorder": border,
            "editorGroupHeader.noTabsBackground": surface,
            "minimap.background": bg, "minimap.selectionHighlight": selection, "minimap.findMatchHighlight": c.accent,
            "minimapSlider.background": selection + "40", "minimapSlider.hoverBackground": selection + "80",
            "minimapSlider.activeBackground": selection + "cc",
            "diffEditor.insertedTextBackground": green + "26", "diffEditor.removedTextBackground": red + "26",
            "diffEditor.insertedLineBackground": green + "14", "diffEditor.removedLineBackground": red + "14",
            "diffEditor.border": border, "diffEditor.diagonalFill": border,

            // Widgets
            "editorWidget.background": elevated, "editorWidget.border": border, "editorWidget.foreground": c.label,
            "editorWidget.resizeBorder": c.accent,
            "editorHoverWidget.background": elevated, "editorHoverWidget.border": border,
            "editorHoverWidget.foreground": c.label, "editorHoverWidget.statusBarBackground": surface,
            "editorSuggestWidget.background": elevated, "editorSuggestWidget.border": border,
            "editorSuggestWidget.foreground": c.label, "editorSuggestWidget.selectedBackground": selection,
            "editorSuggestWidget.selectedForeground": c.label, "editorSuggestWidget.highlightForeground": c.accent,
            "editorSuggestWidget.focusHighlightForeground": c.accent,
            "peekView.border": c.accent, "peekViewTitle.background": elevated, "peekViewTitleLabel.foreground": c.label,
            "peekViewTitleDescription.foreground": c.muted, "peekViewEditor.background": surface,
            "peekViewEditorGutter.background": surface, "peekViewEditor.matchHighlightBackground": selection,
            "peekViewResult.background": elevated, "peekViewResult.fileForeground": c.label,
            "peekViewResult.lineForeground": c.muted, "peekViewResult.selectionBackground": selection,
            "peekViewResult.selectionForeground": c.label, "peekViewResult.matchHighlightBackground": selection,
            "debugToolBar.background": elevated, "debugToolBar.border": border,

            // Activity bar, side bar, panel, status bar, title bar
            "activityBar.background": bg, "activityBar.foreground": c.icon, "activityBar.inactiveForeground": c.muted,
            "activityBar.border": border, "activityBar.activeBorder": c.accent, "activityBar.activeFocusBorder": c.accent,
            "activityBarBadge.background": c.accent, "activityBarBadge.foreground": bg,
            "activityBarTop.foreground": c.icon, "activityBarTop.inactiveForeground": c.muted,
            "activityBarTop.activeBorder": c.accent,
            "sideBar.background": elevated, "sideBar.foreground": c.label, "sideBar.border": border,
            "sideBar.dropBackground": selection + "80", "sideBarTitle.foreground": c.label,
            "sideBarSectionHeader.background": elevated, "sideBarSectionHeader.foreground": c.label,
            "sideBarSectionHeader.border": border,
            "sideBarStickyScroll.background": elevated, "sideBarStickyScroll.border": border,
            "panel.background": elevated, "panel.border": border, "panelTitle.activeBorder": c.accent,
            "panelTitle.activeForeground": c.label, "panelTitle.inactiveForeground": c.muted,
            "panelSection.border": border, "panelSectionHeader.background": surface, "panelInput.border": border,
            "panelStickyScroll.background": elevated,
            "statusBar.background": bg, "statusBar.foreground": c.label, "statusBar.border": border,
            "statusBar.focusBorder": c.accent, "statusBar.noFolderBackground": bg, "statusBar.noFolderForeground": c.label,
            "statusBar.debuggingBackground": yellow, "statusBar.debuggingForeground": bg,
            "statusBarItem.hoverBackground": active, "statusBarItem.activeBackground": selection,
            "statusBarItem.focusBorder": c.accent, "statusBarItem.prominentBackground": selection,
            "statusBarItem.prominentHoverBackground": active,
            "statusBarItem.remoteBackground": c.accent, "statusBarItem.remoteForeground": bg,
            "statusBarItem.errorBackground": red, "statusBarItem.errorForeground": bg,
            "statusBarItem.warningBackground": yellow, "statusBarItem.warningForeground": bg,
            "titleBar.activeBackground": bg, "titleBar.activeForeground": c.label,
            "titleBar.inactiveBackground": bg, "titleBar.inactiveForeground": c.muted, "titleBar.border": border,
            "commandCenter.background": surface, "commandCenter.foreground": c.label, "commandCenter.border": border,
            "commandCenter.activeBackground": active, "commandCenter.activeForeground": c.label,
            "commandCenter.inactiveForeground": c.muted, "commandCenter.inactiveBorder": border,
            "menu.background": elevated, "menu.foreground": c.label, "menu.border": border,
            "menu.selectionBackground": selection, "menu.selectionForeground": c.label,
            "menu.separatorBackground": border, "menubar.selectionBackground": active,

            // Tabs and breadcrumbs
            "tab.activeBackground": bg, "tab.activeForeground": c.label, "tab.inactiveBackground": surface,
            "tab.inactiveForeground": c.muted, "tab.activeBorder": c.accent, "tab.activeBorderTop": c.accent,
            "tab.border": border, "tab.hoverBackground": elevated, "tab.hoverForeground": c.label,
            "tab.unfocusedActiveBackground": bg, "tab.unfocusedActiveForeground": c.muted,
            "tab.unfocusedInactiveForeground": c.muted, "tab.unfocusedActiveBorderTop": c.muted,
            "tab.unfocusedHoverBackground": elevated, "tab.lastPinnedBorder": border,
            "tab.activeModifiedBorder": c.function, "tab.inactiveModifiedBorder": c.muted,
            "breadcrumb.background": surface, "breadcrumb.foreground": c.muted,
            "breadcrumb.focusForeground": c.label, "breadcrumb.activeSelectionForeground": c.accent,
            "breadcrumbPicker.background": elevated,

            // Lists and trees
            "list.activeSelectionBackground": selection, "list.activeSelectionForeground": c.label,
            "list.inactiveSelectionBackground": surface, "list.inactiveSelectionForeground": c.label,
            "list.hoverBackground": active, "list.hoverForeground": c.label, "list.focusBackground": selection,
            "list.focusForeground": c.label, "list.highlightForeground": c.accent, "list.focusOutline": c.accent,
            "list.inactiveFocusBackground": surface, "list.dropBackground": selection + "80",
            "list.errorForeground": red, "list.warningForeground": yellow, "list.invalidItemForeground": red,
            "tree.indentGuidesStroke": border,
            "gitDecoration.addedResourceForeground": green, "gitDecoration.untrackedResourceForeground": green,
            "gitDecoration.modifiedResourceForeground": yellow, "gitDecoration.stageModifiedResourceForeground": yellow,
            "gitDecoration.deletedResourceForeground": red, "gitDecoration.stageDeletedResourceForeground": red,
            "gitDecoration.renamedResourceForeground": cyan, "gitDecoration.conflictingResourceForeground": magenta,
            "gitDecoration.ignoredResourceForeground": c.muted, "gitDecoration.submoduleResourceForeground": blue,

            // Controls
            "button.background": c.accent, "button.foreground": bg, "button.hoverBackground": c.function,
            "button.secondaryBackground": surface, "button.secondaryForeground": c.label,
            "button.secondaryHoverBackground": elevated,
            "extensionButton.prominentBackground": c.accent, "extensionButton.prominentForeground": bg,
            "extensionButton.prominentHoverBackground": c.function,
            "extensionBadge.remoteBackground": c.accent, "extensionBadge.remoteForeground": bg,
            "extensionIcon.starForeground": yellow,
            "input.background": bg, "input.foreground": c.label, "input.border": border,
            "input.placeholderForeground": c.muted, "inputOption.activeBackground": c.accent,
            "inputOption.activeForeground": bg, "inputOption.activeBorder": c.accent,
            "inputValidation.errorBackground": surface, "inputValidation.errorBorder": red,
            "inputValidation.warningBackground": surface, "inputValidation.warningBorder": yellow,
            "inputValidation.infoBackground": surface, "inputValidation.infoBorder": blue,
            "dropdown.background": elevated, "dropdown.listBackground": elevated, "dropdown.foreground": c.label,
            "dropdown.border": border,
            "checkbox.background": surface, "checkbox.foreground": c.label, "checkbox.border": border,
            "keybindingLabel.background": surface, "keybindingLabel.foreground": c.label,
            "keybindingLabel.border": border, "keybindingLabel.bottomBorder": border,
            "badge.background": c.accent, "badge.foreground": bg, "progressBar.background": c.accent,
            "scrollbarSlider.background": selection + "80", "scrollbarSlider.hoverBackground": selection + "cc",
            "scrollbarSlider.activeBackground": selection + "cc",

            // Notifications, quick input, settings, welcome
            "notifications.background": elevated, "notifications.foreground": c.label, "notifications.border": border,
            "notificationCenter.border": border, "notificationCenterHeader.background": elevated,
            "notificationCenterHeader.foreground": c.label, "notificationToast.border": border,
            "notificationsErrorIcon.foreground": c.accent, "notificationsWarningIcon.foreground": c.function,
            "notificationsInfoIcon.foreground": c.icon, "notificationLink.foreground": c.icon,
            "banner.background": selection, "banner.foreground": c.label, "banner.iconForeground": c.icon,
            "quickInput.background": elevated, "quickInput.foreground": c.label,
            "quickInputList.focusBackground": selection, "quickInputList.focusForeground": c.label,
            "quickInputList.focusIconForeground": c.label, "quickInputTitle.background": elevated,
            "pickerGroup.foreground": c.accent, "pickerGroup.border": border,
            "settings.headerForeground": c.label, "settings.modifiedItemIndicator": c.accent,
            "settings.focusedRowBackground": active, "settings.rowHoverBackground": surface,
            "settings.focusedRowBorder": c.accent, "settings.dropdownBackground": elevated,
            "settings.checkboxBackground": surface, "settings.textInputBackground": bg,
            "settings.numberInputBackground": bg,
            "welcomePage.background": bg, "welcomePage.tileBackground": surface,
            "welcomePage.tileHoverBackground": active, "welcomePage.progress.foreground": c.accent,
            "walkThrough.embeddedEditorBackground": elevated,
            "charts.foreground": c.label, "charts.lines": c.muted, "charts.red": red, "charts.blue": blue,
            "charts.yellow": yellow, "charts.orange": s[11].hex, "charts.green": green, "charts.purple": magenta,

            // Terminal
            "terminal.background": bg, "terminal.foreground": s.foreground.hex,
            "terminal.border": border, "terminal.selectionBackground": selection,
            "terminal.inactiveSelectionBackground": surface, "terminal.findMatchBackground": selection,
            "terminalCursor.background": bg, "terminalCursor.foreground": c.accent,
            "terminalCommandDecoration.defaultBackground": c.muted,
            "terminalCommandDecoration.successBackground": green, "terminalCommandDecoration.errorBackground": red,
            "terminal.ansiBlack": s[0].hex, "terminal.ansiRed": red, "terminal.ansiGreen": green,
            "terminal.ansiYellow": yellow, "terminal.ansiBlue": blue, "terminal.ansiMagenta": magenta,
            "terminal.ansiCyan": cyan, "terminal.ansiWhite": s[7].hex,
            "terminal.ansiBrightBlack": s[8].hex, "terminal.ansiBrightRed": s[9].hex,
            "terminal.ansiBrightGreen": s[10].hex, "terminal.ansiBrightYellow": s[11].hex,
            "terminal.ansiBrightBlue": s[12].hex, "terminal.ansiBrightMagenta": s[13].hex,
            "terminal.ansiBrightCyan": s[14].hex, "terminal.ansiBrightWhite": s[15].hex,
        ]
    }

    /// Syntax colours, as TextMate rules: the broad scopes first, the
    /// specific ones after them (later rules win).
    static func vscodeTokenRules(_ s: Scheme) -> [[String: Any]] {
        let c = palette(s)
        func rule(_ scope: Any, _ color: String?, _ style: String? = nil) -> [String: Any] {
            var settings: [String: String] = [:]
            if let color { settings["foreground"] = color }
            if let style { settings["fontStyle"] = style }
            return ["scope": scope, "settings": settings]
        }
        return [
            rule(["comment", "punctuation.definition.comment"], c.comment, "italic"),
            rule(["keyword", "keyword.control", "storage"], c.keyword, "bold"),
            rule(["entity.name.function", "meta.function-call"], c.function, "bold"),
            rule(["variable", "meta.definition.variable"], c.label),
            rule(["string", "string.quoted"], c.string),
            rule(["entity.name.type", "support.type", "support.class"], c.type, "bold"),
            rule(["constant.numeric", "keyword.other.unit"], c.keywordDim),
            rule(["storage.type", "storage.modifier"], c.keyword, "bold"),
            rule(["entity.name.type", "entity.name.class", "entity.other.inherited-class"], c.type, "bold"),
            rule(["entity.name.type.interface", "entity.name.type.type-parameter", "entity.name.type.parameter"], c.typeLight, "bold"),
            rule("entity.name.type.enum", c.typeLight, "bold"),
            rule(["variable.other.enummember", "entity.name.namespace", "entity.name.type.namespace"], c.typeDim),
            rule(["entity.name.function", "support.function"], c.function, "bold"),
            rule("entity.name.function.member", c.functionLight, "bold"),
            rule("entity.name.function.constructor", c.functionLight, "bold"),
            rule("variable.parameter", c.parameter, "italic"),
            rule(["constant.language", "support.constant", "variable.other.constant"], c.keywordLight, "bold"),
            rule("constant.numeric", c.keywordDim),
            rule(["variable.other.property", "variable.other.object.property", "support.type.property-name", "meta.object-literal.key"], c.property),
            rule(["variable.language", "variable.language.this", "variable.language.self", "support.variable"], c.variableSpecial, "italic"),
            rule("punctuation.definition.string", c.stringDim),
            rule("constant.character.escape", c.stringDim),
            rule("string.regexp", c.stringLight),
            rule("string.template", c.string),
            rule(["punctuation.definition.template-expression", "punctuation.section.embedded"], c.keywordDim),
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
            rule(["markup.heading", "entity.name.section"], c.keyword, "bold"),
            rule("markup.bold", nil, "bold"),
            rule("markup.italic", nil, "italic"),
            rule(["markup.inline.raw", "markup.fenced_code", "markup.raw"], c.string),
            rule(["markup.underline.link", "string.other.link"], c.icon),
            rule("markup.quote", c.comment, "italic"),
            rule("markup.inserted", s[2].hex),
            rule("markup.deleted", s[1].hex),
            rule("markup.changed", s[3].hex),
            rule("invalid", s[1].hex),
        ]
    }

    // MARK: Gemini CLI

    /// A "Tint" custom theme in `~/.gemini/settings.json`, selected when it
    /// is first added (or when no theme is set); after that, the theme you pick stays.
    static func gemini(_ s: Scheme, folder: String) throws -> [String] {
        guard TintPaths.isDirectory(folder) else { return [] }
        let path = folder + "/settings.json"
        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? "{}\n"
        guard let settings = JSONCEditor.parse(text) as? [String: Any] else { throw Failure.notJSON(path) }
        var ui = settings["ui"] as? [String: Any] ?? [:]
        var custom = ui["customThemes"] as? [String: Any] ?? [:]
        let firstTime = custom[themeName] == nil
        custom[themeName] = geminiTheme(s)
        ui["customThemes"] = custom
        if firstTime || ui["theme"] == nil { ui["theme"] = themeName }

        var editor = JSONCEditor(text)
        try editor.set("ui", ui)
        try PywalWriter.atomicWrite(editor.text, to: path)
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
        var bg, surface, elevated, active, border, selection: String
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
        let background = s.background.lab
        // Panels, tabs and highlights step away from the background in
        // lightness only — lighter on dark themes, darker on light ones — so
        // they keep its colour instead of fading to grey.
        func layer(_ step: Double) -> String {
            background.withLightness(min(max(background.l + (dark ? step : -step * 0.6), 0), 100)).inGamut().rgb.hex
        }
        // The selection: the background, a third of the way to the blue.
        let blue = s[4].lab
        let selection = Lab(
            l: background.l + (blue.l - background.l) * 0.3,
            a: background.a + (blue.a - background.a) * 0.3,
            b: background.b + (blue.b - background.b) * 0.3
        ).inGamut().rgb.hex
        let label = s[6], c8 = s[8]
        return Roles(
            bg: s.background.hex, surface: layer(3), elevated: layer(6), active: layer(9), border: layer(12),
            selection: selection,
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
        try PywalWriter.atomicWrite(try jsonText(object), to: path)
    }

    /// `object` as the text `writeJSON` writes.
    static func jsonText(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self) + "\n"
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
