import Foundation
import Testing
@testable import TintCore

struct SetupTests {
    let context = ReloadContext(scheme: testScheme, wallpaper: "/walls/city.jpg", cacheDirectory: "/tmp/wal")

    @Test func settingsRoundTrip() throws {
        let dir = TempDir()
        try TintSettings(mode: nil, saturation: 1.25).save(to: dir.file("settings.json"))
        #expect(TintSettings.load(from: dir.file("settings.json")) == TintSettings(mode: nil, saturation: 1.25))
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
        let result = try ThemeApplier.apply(palette: SchemeTests.night, wallpaper: "/walls/koi.jpg", options: options, reloaders: [])

        #expect(result.scheme.mode == .light)
        #expect(ThemeApplier.lastApplied(cacheDirectory: dir.file("wal")) == "/walls/koi.jpg")
    }
}
