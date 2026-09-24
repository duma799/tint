import ArgumentParser
import Dispatch
import Foundation
import TintCore

/// `tint watch` — wait for wallpaper changes and theme everything from each
/// new one. Replaces pywal hooks: no lock files, no sleeps.
struct Watch: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Watch for wallpaper changes and apply a theme from each one.")

    @Flag(name: .shortAndLong, help: "Show raw file events and how the wallpaper was found.")
    var verbose = false

    @Flag(help: "Only show each new palette; don't change any themes.")
    var noApply = false

    @OptionGroup var theme: ThemeOptions

    func run() throws {
        let verbose = verbose, apply = !noApply, mode = theme.mode, saturation = theme.saturation

        let watcher = WallpaperWatcher(directories: MacWallpaper.watchDirectories) {
            let lookup = MacWallpaper.current()
            if verbose { lookup.trace.forEach { Terminal.log("  · \($0)") } }
            if lookup.path == nil, let notice = lookup.notice { Notices.shared.show(notice) }
            return lookup.path
        }
        if verbose { watcher.onTrace = { Terminal.log("  · \($0)") } }

        // Changes arrive one at a time on the watcher's own queue, so applies never overlap.
        watcher.onChange = { path in
            Terminal.log("wallpaper changed → \(path)")
            Notices.shared.reset()
            if apply {
                // Something else (`tint apply -w`, the app) already themed from
                // this image, maybe with other options: keep that.
                if ThemeApplier.lastApplied() == path {
                    Terminal.log("already themed from it")
                    return
                }
                // Read the saved settings on every change, not once: a mode picked
                // in the app then applies without restarting the service.
                _ = Apply.run(path, ApplyOptions.resolved(mode: mode, saturation: saturation), compact: true)
            } else if let palette = try? PaletteExtractor.extract(file: path) {
                Terminal.log("palette: \(Terminal.strip(palette))  \(palette.swatches.count) colours, \(palette.isDark ? "dark" : "light")")
            } else {
                Terminal.log("couldn't read it")
            }
        }

        watcher.start()

        // In system mode, re-theme the same wallpaper when macOS switches
        // between dark and light (by hand, or by itself at sunset).
        #if os(macOS)
        Appearance.observer = DistributedNotificationCenter.default().addObserver(
            forName: SystemAppearance.changedNotification, object: nil, queue: nil
        ) { _ in
            let options = ApplyOptions.resolved(mode: mode, saturation: saturation)
            guard apply, options.mode == .system, let path = ThemeApplier.lastApplied() else { return }
            Terminal.log("macOS switched to \(SystemAppearance.isDark() ? "dark" : "light") mode")
            watcher.queue.async { _ = Apply.run(path, options, compact: true) }
        }
        #endif
        let what = apply ? "applying a theme on each change" : "preview only (--no-apply)"
        Terminal.log("watching for wallpaper changes, \(what) — Ctrl+C to stop")
        Terminal.log("current: \(MacWallpaper.current().path ?? "unknown")")

        // Stop cleanly on Ctrl+C and on `launchctl bootout` (SIGTERM).
        for signalNumber in [SIGINT, SIGTERM] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler {
                watcher.stop()
                Terminal.log("stopped")
                Foundation.exit(0)
            }
            source.resume()
            Signals.keep.append(source)
        }

        // Run the main run loop forever: AppKit's screen lookups run on the
        // main queue, and AppKit only learns about system changes (like a new
        // wallpaper) while the run loop turns — dispatchMain() never turns it.
        while true { RunLoop.main.run(mode: .default, before: .distantFuture) }
    }
}

/// Tells the user something once; repeats of the same message are dropped
/// until the wallpaper becomes readable again.
final class Notices: @unchecked Sendable {
    static let shared = Notices()
    private let lock = NSLock()
    private var last: String?

    func show(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        guard message != last else { return }
        last = message
        Terminal.log("note: \(message)")
    }

    func reset() {
        lock.lock()
        last = nil
        lock.unlock()
    }
}

enum Signals {
    nonisolated(unsafe) static var keep: [any DispatchSourceSignal] = []
}

enum Appearance {
    nonisolated(unsafe) static var observer: (any NSObjectProtocol)?
}
