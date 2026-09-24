import Foundation
import Testing
@testable import TintCore

struct WallpaperStoreTests {
    static func choice(_ provider: String, file: String? = nil, configuration: Data = Data("bplist00".utf8)) -> [String: Any] {
        ["Configuration": configuration, "Files": file.map { [["relative": $0]] } ?? [], "Provider": provider]
    }

    static func slot(_ choice: [String: Any]) -> [String: Any] {
        ["Content": ["Choices": [choice], "Shuffle": "$null"]]
    }

    static func read(_ root: [String: Any]) throws -> MacWallpaperStore.Choice {
        MacWallpaperStore.read(plist: try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0))
    }

    @Test func readsTheDesktopPictureAndDecodesTheFileURL() throws {
        let choice = try Self.read(["AllSpacesAndDisplays": [
            "Desktop": Self.slot(Self.choice("com.apple.wallpaper.choice.image", file: "file:///Users/duma/Pictures/City%20Night.jpg")),
            "Type": "individual",
        ]])
        #expect(choice == .init(file: "/Users/duma/Pictures/City Night.jpg", provider: "com.apple.wallpaper.choice.image"))
    }

    @Test func ignoresTheScreenSaver() throws {
        let choice = try Self.read(["AllSpacesAndDisplays": [
            "Idle": Self.slot(Self.choice("com.apple.wallpaper.choice.image", file: "file:///saver.jpg")),
            "Desktop": Self.slot(Self.choice("com.apple.wallpaper.choice.image", file: "file:///desk.jpg")),
        ]])
        #expect(choice.file == "/desk.jpg")
    }

    @Test func prefersTheAllDisplaysSettingOverAPerDisplayOne() throws {
        let choice = try Self.read([
            "Displays": ["A1B2": ["Desktop": Self.slot(Self.choice("com.apple.wallpaper.choice.image", file: "file:///old.jpg"))]],
            "AllSpacesAndDisplays": ["Desktop": Self.slot(Self.choice("com.apple.wallpaper.choice.image", file: "file:///new.jpg"))],
        ])
        #expect(choice.file == "/new.jpg")
    }

    @Test func anAerialWallpaperHasAProviderButNoFile() throws {
        let choice = try Self.read(["AllSpacesAndDisplays": ["Desktop": Self.slot(Self.choice("com.apple.wallpaper.choice.aerials"))]])
        #expect(choice == .init(file: nil, provider: "com.apple.wallpaper.choice.aerials"))
    }

    @Test func realMacOS26LayoutFindsTheFileInsideTheNestedConfiguration() throws {
        // A picture wallpaper has an EMPTY "Files" array; its path lives inside
        // "Configuration", a second binary plist.
        let nested = try PropertyListSerialization.data(
            fromPropertyList: ["url": ["relative": "file:///Users/duma/Pictures/koi.jpg"]], format: .binary, options: 0)
        let choice = try Self.read(["AllSpacesAndDisplays": [
            "Desktop": Self.slot(Self.choice("com.apple.wallpaper.choice.image", configuration: nested)),
            "Idle": Self.slot(Self.choice("com.apple.wallpaper.choice.macintosh")),
        ], "Displays": [String: Any](), "Spaces": [String: Any]()])
        #expect(choice == .init(file: "/Users/duma/Pictures/koi.jpg", provider: "com.apple.wallpaper.choice.image"))
    }

    @Test func garbageIsNoChoice() {
        #expect(MacWallpaperStore.read(plist: Data("nope".utf8)) == .init(file: nil, provider: nil))
    }

    @Test func snapshotFolderNamesCoverExtensionsAndThePictureProvider() {
        #expect(MacWallpaperStore.snapshotFolderNames(provider: "com.apple.NeptuneOneExtension") == ["extension-com.apple.NeptuneOneExtension"])
        #expect(MacWallpaperStore.snapshotFolderNames(provider: "com.apple.wallpaper.choice.image")
            == ["extension-com.apple.wallpaper.choice.image", "extension-com.apple.wallpaper.extension.image"])
    }

    @Test func newestSnapshotWinsAndNonImagesAreIgnored() throws {
        let dir = TempDir()
        let fm = FileManager.default
        let old = dir.write("a.bmp", "old"), new = dir.write("b.bmp", "new"), _ = dir.write("c.txt", "text"), _ = dir.write("d.bmp", "")
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)], ofItemAtPath: old)
        try fm.setAttributes([.modificationDate: Date()], ofItemAtPath: new)
        #expect(MacWallpaperStore.newestSnapshot(in: dir.path) == new)
        #expect(MacWallpaperStore.newestSnapshot(in: dir.file("missing")) == nil)
    }
}

struct WatcherTests {
    final class Box: @unchecked Sendable {
        var value: String?
        var changes: [String] = []
    }

    @Test func reportsOnlyRealChanges() {
        let box = Box()
        box.value = "/a.jpg"
        let watcher = WallpaperWatcher(directories: []) { box.value }
        watcher.onChange = { box.changes.append($0) }
        watcher.start()
        defer { watcher.stop() }

        watcher.checkNow() // same as at start
        box.value = "/b.jpg"
        watcher.checkNow()
        watcher.checkNow() // unchanged
        box.value = nil // unreadable for a moment: not a change
        watcher.checkNow()
        box.value = "/b.jpg"
        watcher.checkNow()

        #expect(box.changes == ["/b.jpg"])
    }

    @Test func aBurstOfEventsLeadsToOneCheck() async throws {
        let box = Box()
        box.value = "/a.jpg"
        // Generous margins: CI machines can be slow to schedule.
        let watcher = WallpaperWatcher(directories: [], settle: 1.0) { box.value }
        watcher.onChange = { box.changes.append($0) }
        watcher.start()
        defer { watcher.stop() }

        box.value = "/b.jpg"
        for _ in 0..<5 { watcher.trigger() }
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(box.changes.isEmpty) // still settling

        for _ in 0..<50 where box.changes.isEmpty {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        #expect(box.changes == ["/b.jpg"])
    }
}
