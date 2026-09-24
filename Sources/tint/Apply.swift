import ArgumentParser
import Foundation
import TintCore

/// `tint apply [image]` — theme everything from an image (default: the current wallpaper).
struct Apply: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Generate a colour scheme from an image and apply it everywhere.")

    @Argument(help: "Image to theme from. Defaults to the current wallpaper.", completion: .file())
    var image: String?

    @OptionGroup var theme: ThemeOptions

    @Flag(help: "Only write the files; don't tell apps to reload.")
    var noReload = false

    @Flag(name: [.customShort("w"), .long], help: "Also make the image the desktop wallpaper.")
    var setWallpaper = false

    func run() throws {
        let path: String
        if let image {
            path = URL(fileURLWithPath: image).standardizedFileURL.path
        } else {
            let lookup = MacWallpaper.current()
            guard let current = lookup.path else {
                Terminal.error(lookup.notice ?? "no image given and couldn't find the current wallpaper.")
                throw ExitCode.failure
            }
            path = current
        }

        guard let result = Apply.run(path, theme.resolved(reload: !noReload), compact: false) else { throw ExitCode.failure }

        // After the theme exists: a running `tint watch` then finds this
        // wallpaper already themed, and a failed theme leaves the desktop alone.
        if setWallpaper && image != nil {
            do {
                try MacWallpaper.set(path)
                say("  ✓ set as the wallpaper")
            } catch {
                Terminal.error("\(error)")
                throw ExitCode.failure
            }
        }

        if result.reloads.contains(where: { !$0.ok }) { throw ExitCode.failure }
    }

    /// Applies and prints the outcome; nil if no theme could be made. Shared with `tint watch`.
    static func run(_ path: String, _ options: ApplyOptions, compact: Bool) -> ApplyResult? {
        if !compact {
            // Before applying, so any output from the user's hook comes after it.
            say("  \(path)")
        }

        let result: ApplyResult
        do {
            result = try ThemeApplier.apply(image: path, options: options)
        } catch {
            Terminal.error("\(error)")
            return nil
        }

        let s = result.scheme
        if compact {
            let reloaded = result.reloads.filter { $0.ok && !$0.skipped }.map(\.name) + result.reloads.filter { !$0.ok }.map { "\($0.name) ✗" }
            Terminal.log("applied: \(Terminal.strip(s))  \(s.mode.rawValue), \(result.written.count) files" + (reloaded.isEmpty ? "" : " → " + reloaded.joined(separator: ", ")))
        } else {
            say("  \(Terminal.block(s.background, 2)) background \(s.background.hex)   \(Terminal.block(s.foreground, 2)) foreground \(s.foreground.hex)   (\(s.mode.rawValue))")
            say("  " + s.colors[0..<8].map { Terminal.block($0, 4) }.joined())
            say("  " + s.colors[8..<16].map { Terminal.block($0, 4) }.joined())
            say("  wrote \(result.written.count) files to \(options.cacheDirectory)")
            if let apollo = result.written.first(where: { $0.hasSuffix("/" + ApolloShellTheme.fileName) }) {
                say("  ✓ ApolloShell theme       \(apollo)")
            }
            for r in result.reloads {
                let mark = r.skipped ? "·" : r.ok ? "✓" : "✗"
                say("  \(mark) \(r.name.padding(toLength: 20, withPad: " ", startingAt: 0)) \(r.detail)")
            }
        }
        result.warnings.forEach(Terminal.warn)
        return result
    }
}
