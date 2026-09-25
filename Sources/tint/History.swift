import ArgumentParser
import Foundation
import TintCore

/// `tint back [n]` — undo the latest theme.
struct Back: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Bring back the previous theme (and its wallpaper).")

    @Argument(help: "How many themes to go back.")
    var steps = 1

    func run() throws {
        do {
            guard let (entry, result) = try ThemeApplier.back(steps: steps) else {
                Terminal.error("no earlier theme to go back to — see `tint history`.")
                throw ExitCode.failure
            }
            say("  back to \((entry.wallpaper as NSString).lastPathComponent) (\(entry.mode.rawValue), \(History.format(entry.date)))")
            say("  \(Terminal.strip(result.scheme))")
        } catch let exit as ExitCode {
            throw exit
        } catch {
            Terminal.error("\(error)")
            throw ExitCode.failure
        }
    }
}

/// `tint history` — the themes applied lately.
struct History: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List the latest themes, newest first.")

    @Option(name: .shortAndLong, help: "How many to show.")
    var count = 10

    func run() throws {
        let entries = ThemeHistory.load()
        guard !entries.isEmpty else {
            say("  no themes yet")
            return
        }
        for (i, entry) in entries.prefix(count).enumerated() {
            let strip = entry.colors.compactMap(Rgb.init(hex:)).map { Terminal.block($0, 1) }.joined()
            let label = i == 0 ? "now " : "-\(i)".padding(toLength: 4, withPad: " ", startingAt: 0)
            say("  \(label) \(strip)  \(History.format(entry.date))  \(entry.mode.rawValue)  \((entry.wallpaper as NSString).lastPathComponent)")
        }
        if entries.count > 1 { say("\n  tint back [n] brings one back") }
    }

    static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "MMM d HH:mm"
        return formatter.string(from: date)
    }
}

/// `tint pause` / `tint resume` — let the watcher ignore wallpaper changes for a while.
struct PauseCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "pause", abstract: "Stop re-theming on wallpaper changes until `tint resume`.")

    func run() throws {
        try Pause.set(true)
        say("  paused — the watcher leaves wallpaper changes alone until `tint resume`")
    }
}

struct Resume: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Re-theme on wallpaper changes again.")

    func run() throws {
        try Pause.set(false)
        say("  resumed")
    }
}
