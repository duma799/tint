import Foundation
import Testing
@testable import TintCore

struct SetupTests {
    let context = ReloadContext(scheme: testScheme, wallpaper: "/walls/city.jpg", cacheDirectory: "/tmp/wal")

    @Test func settingsRoundTrip() throws {
        let dir = TempDir()
        try TintSettings(mode: .system, saturation: 1.25).save(to: dir.file("settings.json"))
        #expect(TintSettings.load(from: dir.file("settings.json")) == TintSettings(mode: .system, saturation: 1.25))
    }

    @Test(arguments: ["not json", "[1, 2]", "{\"mode\": 3}"])
    func brokenSettingsFallBackToTheDefaults(content: String) {
        let dir = TempDir()
        #expect(TintSettings.load(from: dir.write("settings.json", content)) == TintSettings())
    }

    @Test func missingSettingsAreTheDefaultsAndSaturationIsClamped() {
        let dir = TempDir()
        #expect(TintSettings.load(from: dir.file("none.json")) == TintSettings())
        let loaded = TintSettings.load(from: dir.write("settings.json", "{\"mode\": \"light\", \"saturation\": 9}"))
        #expect(loaded == TintSettings(mode: .light, saturation: 1.5))
    }

    @Test func modePreferencesResolve() {
        let dark = palette("#10141f", "#1b2233", "#2a3450"), light = palette("#f4efe6", "#d8d2c4", "#b0a890")
        #expect(ModePreference.dark.resolve(for: light) == .dark)
        #expect(ModePreference.light.resolve(for: dark) == .light)
        #expect(ModePreference.auto.resolve(for: dark) == .dark)
        #expect(ModePreference.auto.resolve(for: light) == .light)
        #expect(ModePreference.system.resolve(for: dark, systemIsDark: { false }) == .light)
        #expect(ModePreference.system.resolve(for: light, systemIsDark: { true }) == .dark)
        #expect(ModePreference(name: "nonsense") == .dark)
    }

    @Test func hookRunsWithTheWallpaperAndModeInItsEnvironment() {
        let dir = TempDir()
        dir.write("hooks/post-apply", "#!/bin/sh\necho \"$TINT_WALLPAPER|$TINT_MODE|$TINT_CACHE\" > \"\(dir.file("out"))\"\n", executable: true)
        let result = HookReloader(hooksDirectory: dir.file("hooks")).reload(context)
        #expect(result.ok && !result.skipped)
        #expect(dir.read("out") == "/walls/city.jpg|dark|/tmp/wal\n")
    }

    @Test func aNonExecutableHookIsReportedNotRun() {
        let dir = TempDir()
        dir.write("hooks/post-apply", "#!/bin/sh\n")
        let result = HookReloader(hooksDirectory: dir.file("hooks")).reload(context)
        #expect(!result.ok)
        #expect(result.detail.contains("chmod +x"))
    }

    @Test func noHookIsSimplySkipped() {
        let result = HookReloader(hooksDirectory: "/nonexistent").reload(context)
        #expect(result.ok && result.skipped)
    }

    @Test func ghosttyIsOnlyReloadedWhenItsConfigUsesTintsTheme() {
        let dir = TempDir()
        let config = dir.write("config", "font-size = 14\n")
        #expect(!GhosttyReloader(configFiles: [config]).usesTintTheme())
        dir.write("config", "font-size = 14\nconfig-file = ~/.cache/wal/colors-ghostty\n")
        #expect(GhosttyReloader(configFiles: [config]).usesTintTheme())
    }

    @Test func appsThatAreNotRunningAreSkipped() {
        let reloaders: [any Reloader] = [SketchyBarReloader(), BordersReloader(bordersrc: "/nonexistent"), GhosttyReloader(configFiles: [])]
        for r in reloaders {
            let result = r.reload(context)
            #expect(result.ok && result.skipped, "\(result.name): \(result.detail)")
        }
    }

    @Test func launchAgentPlistIsValidAndEscapesItsValues() throws {
        let plist = LaunchAgent.plist(
            programArguments: ["/Users/me/tools & things/tint", "watch"],
            environment: ["PATH": "/opt/homebrew/bin:/usr/bin"],
            log: "/Users/me/Library/Logs/tint.log")
        #expect(plist.contains("<string>/Users/me/tools &amp; things/tint</string>"))
        #expect(LaunchAgent.programArguments(fromPlist: Data(plist.utf8)) == ["/Users/me/tools & things/tint", "watch"])
        let parsed = try PropertyListSerialization.propertyList(from: Data(plist.utf8), format: nil) as? [String: Any]
        #expect(parsed?["Label"] as? String == LaunchAgent.label)
        #expect((parsed?["EnvironmentVariables"] as? [String: String])?["PATH"] == "/opt/homebrew/bin:/usr/bin")
    }

    @Test func servicePathKeepsTheUsersPathAndAddsHomebrewOnce() {
        let path = LaunchAgent.servicePath("/Users/me/.local/bin:/usr/bin")
        #expect(path.hasPrefix("/Users/me/.local/bin:/usr/bin:/opt/homebrew/bin"))
        #expect(path.split(separator: ":").filter { $0 == "/usr/bin" }.count == 1)
    }

    @Test func readsThePidFromLaunchctlPrint() {
        #expect(LaunchAgent.pid(fromLaunchctlPrint: "\tstate = running\n\tpid = 4242\n") == 4242)
        #expect(LaunchAgent.pid(fromLaunchctlPrint: "\tstate = not running\n") == nil)
    }

    @Test func applyWritesTheThemeAndRemembersTheImage() throws {
        let dir = TempDir()
        var options = ApplyOptions(mode: .light, saturation: 1.2, reload: true)
        options.cacheDirectory = dir.file("wal")
        options.templatesDirectory = nil
        options.apolloShellThemes = nil
        options.editors = nil
        options.history = nil
        let result = try ThemeApplier.apply(palette: SchemeTests.night, wallpaper: "/walls/koi.jpg", options: options, reloaders: [])

        #expect(result.scheme.mode == .light)
        #expect(ThemeApplier.lastApplied(cacheDirectory: dir.file("wal")) == "/walls/koi.jpg")
    }
}

struct HistoryTests {
    func entry(_ name: String, _ mode: ThemeMode = .dark, at seconds: Double) -> HistoryEntry {
        HistoryEntry(wallpaper: "/walls/\(name).jpg", mode: mode, saturation: 1, date: Date(timeIntervalSince1970: seconds), colors: ["#000000"])
    }

    @Test func newestFirstAndReapplyingOnlyMovesItToTheTop() throws {
        let dir = TempDir()
        let path = dir.file("history.json")
        try ThemeHistory.record(entry("a", at: 1), to: path)
        try ThemeHistory.record(entry("b", at: 2), to: path)
        try ThemeHistory.record(entry("a", at: 3), to: path)
        try ThemeHistory.record(entry("a", .light, at: 4), to: path)

        let names = ThemeHistory.load(from: path).map { ($0.wallpaper as NSString).lastPathComponent + "/" + $0.mode.rawValue }
        #expect(names == ["a.jpg/light", "a.jpg/dark", "b.jpg/dark"])
    }

    @Test func keepsOnlyTheLatest() throws {
        let dir = TempDir()
        let path = dir.file("history.json")
        for i in 0..<(ThemeHistory.limit + 5) { try ThemeHistory.record(entry("w\(i)", at: Double(i)), to: path) }
        let loaded = ThemeHistory.load(from: path)
        #expect(loaded.count == ThemeHistory.limit)
        #expect(loaded.first?.wallpaper == "/walls/w\(ThemeHistory.limit + 4).jpg")
    }

    @Test func applyRecordsTheResolvedTheme() throws {
        let dir = TempDir()
        var options = ApplyOptions(mode: .auto, saturation: 1.2, reload: false)
        options.cacheDirectory = dir.file("wal")
        options.templatesDirectory = nil
        options.apolloShellThemes = nil
        options.editors = nil
        options.history = dir.file("history.json")
        let result = try ThemeApplier.apply(palette: SchemeTests.night, wallpaper: "/walls/koi.jpg", options: options, reloaders: [])

        let recorded = ThemeHistory.load(from: dir.file("history.json"))
        #expect(recorded.count == 1)
        #expect(recorded[0].mode == result.scheme.mode)
        #expect(recorded[0].saturation == 1.2)
        #expect(recorded[0].colors == result.scheme.colors.map(\.hex))
    }

    @Test func displaysResolveByNumberNameOrMain() {
        let displays = [
            DisplayInfo(index: 1, id: 1, uuid: "A", name: "Built-in Retina Display", pixelWidth: 2940, pixelHeight: 1912, isMain: true),
            DisplayInfo(index: 2, id: 2, uuid: "B", name: "LG UltraFine", pixelWidth: 3840, pixelHeight: 2160, isMain: false),
        ]
        #expect(Displays.resolve(nil, among: displays)?.uuid == "A")
        #expect(Displays.resolve("main", among: displays)?.uuid == "A")
        #expect(Displays.resolve("2", among: displays)?.uuid == "B")
        #expect(Displays.resolve("lg", among: displays)?.uuid == "B")
        #expect(Displays.resolve("9", among: displays)?.uuid == "A") // gone: back to main
    }
}
