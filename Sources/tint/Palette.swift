import ArgumentParser
import Foundation
import TintCore

/// `tint palette <image>` — the colours in an image.
struct PaletteCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "palette", abstract: "Extract a colour palette from an image.")

    @Argument(help: "The image.", completion: .file())
    var image: String

    @Option(name: .shortAndLong, help: "How many colours (1–32).")
    var count = 16

    func validate() throws {
        guard (1...32).contains(count) else { throw ValidationError("--count must be between 1 and 32.") }
    }

    func run() throws {
        var options = ExtractOptions()
        options.count = count
        let palette: TintCore.Palette
        do {
            palette = try PaletteExtractor.extract(file: image, options: options)
        } catch {
            Terminal.error("\(error)")
            throw ExitCode.failure
        }

        say()
        for swatch in palette.swatches {
            let share = String(format: "%5.1f%%", swatch.share * 100)
            say("  \(Terminal.block(swatch.color))  \(swatch.color.hex)  \(share)")
        }
        say()
        say("  \(palette.swatches.count) colours · \(palette.isDark ? "dark" : "light") image (lightness \(Int(palette.lightness.rounded())))")
    }
}
