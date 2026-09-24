import ArgumentParser
import TintCore

/// `tint doctor` — check the setup and say what to fix.
struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Check tint's setup: wallpaper access, apps it themes, the service.")

    func run() throws {
        let checks = TintCore.Doctor.run()
        for check in checks {
            let mark = switch check.status {
            case .ok: "✓"
            case .warning: "!"
            case .problem: "✗"
            case .info: "·"
            }
            say("  \(mark) \(check.name.padding(toLength: 13, withPad: " ", startingAt: 0)) \(check.detail)")
        }
        if checks.contains(where: { $0.status == .problem }) { throw ExitCode.failure }
    }
}
