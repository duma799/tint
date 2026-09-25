import ArgumentParser
import Foundation
import TintCore

@main
struct Tint: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tint",
        abstract: "Colour themes from your wallpaper, for macOS.",
        version: tintVersion,
        subcommands: [Apply.self, Back.self, History.self, Watch.self, PauseCommand.self, Resume.self, Service.self, Doctor.self, App.self, PaletteCommand.self, Wallpaper.self, Displays.self])
}

/// --mode and --saturation, shared by apply and watch.
struct ThemeOptions: ParsableArguments {
    @Option(name: .shortAndLong, help: "dark, light, auto (from the image) or system (follow macOS). Default: your saved setting, else dark.")
    var mode: String?

    @Option(name: .shortAndLong, help: "Accent saturation, 0.5–1.5 (1 = the image's own). Default: your saved setting, else 1.")
    var saturation: Double?

    func validate() throws {
        if let mode, ModePreference(rawValue: mode) == nil {
            throw ValidationError("--mode must be dark, light, auto or system.")
        }
        if let saturation, !SchemeBuilder.saturationRange.contains(saturation) {
            throw ValidationError("--saturation must be between 0.5 and 1.5.")
        }
    }

    func resolved(reload: Bool = true) -> ApplyOptions {
        ApplyOptions.resolved(mode: mode, saturation: saturation, reload: reload)
    }
}
