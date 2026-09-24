import ArgumentParser
import Foundation
import TintCore

/// `tint wallpaper` — print the current wallpaper's path.
struct Wallpaper: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Print the path of the current wallpaper.")

    @Flag(name: .shortAndLong, help: "Show how the wallpaper was found.")
    var verbose = false

    func run() throws {
        let lookup = MacWallpaper.current()
        if verbose {
            for line in lookup.trace { FileHandle.standardError.write(Data("  · \(line)\n".utf8)) }
        }
        guard let path = lookup.path else {
            Terminal.error(lookup.notice ?? "couldn't find the current wallpaper.")
            throw ExitCode.failure
        }
        say(path)
    }
}
