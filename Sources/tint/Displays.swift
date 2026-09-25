import ArgumentParser
import Foundation
import TintCore

/// `tint displays [--use <display>]` — which display's wallpaper tint themes from.
struct Displays: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List the displays, or choose which one's wallpaper tint themes from.")

    @Option(help: "main, a number from the list, or part of a display's name.")
    var use: String?

    func run() throws {
        var settings = TintSettings.load()
        if let use {
            settings.display = use
            try settings.save()
            say("  ✓ theming from: \(use)")
        }

        let displays = TintCore.Displays.all()
        guard !displays.isEmpty else {
            say("  no displays found")
            return
        }
        let chosen = TintCore.Displays.resolve(settings.display, among: displays)
        for d in displays {
            let mark = d == chosen ? "●" : " "
            let main = d.isMain ? "  (main)" : ""
            say("  \(mark) \(d.index)  \(d.name)  \(d.pixelWidth)×\(d.pixelHeight)\(main)")
        }
        if displays.count > 1 && use == nil {
            say("\n  tint displays --use <number|main> chooses which one drives the theme")
        }
    }
}
