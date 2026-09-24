import ArgumentParser
import Foundation
import TintCore

/// `tint service install|uninstall|restart|status` — run `tint watch` from login.
struct Service: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run `tint watch` in the background from login (a launchd agent).",
        subcommands: [Install.self, Uninstall.self, Restart.self, Status.self])

    struct Install: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Start watching now and at every login.")

        func run() throws {
            try guarded {
                let program = LaunchAgent.tintCommand(executable: Bundle.main.executablePath ?? CommandLine.arguments[0]) + ["watch"]
                try LaunchAgent.install(programArguments: program)
                say("  ✓ installed \(LaunchAgent.plistPath)")
                say("    runs: \(program.joined(separator: " "))")
                say("    log:  \(TintPaths.log)")
            }
        }
    }

    struct Uninstall: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Stop watching and remove the agent.")

        func run() throws {
            try guarded { say(try LaunchAgent.uninstall() ? "  ✓ removed; tint no longer runs at login" : "  · wasn't installed") }
        }
    }

    struct Restart: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Restart the background watcher (e.g. after updating tint).")

        func run() throws {
            try guarded {
                try LaunchAgent.restart()
                say("  ✓ restarted")
            }
        }
    }

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Is the background watcher running?")

        func run() throws {
            try guarded {
                let s = LaunchAgent.status()
                let state = !s.installed ? "not installed" : s.running ? "running (pid \(s.pid!))" : s.loaded ? "loaded, not running" : "installed, not loaded"
                say("  \(state)")
                if s.installed {
                    say("  runs: \(s.programArguments.joined(separator: " "))")
                    say("  log:  \(TintPaths.log)")
                }
            }
        }
    }
}

private func guarded(_ body: () throws -> Void) throws {
    #if os(macOS)
    do {
        try body()
    } catch {
        Terminal.error("\(error)")
        throw ExitCode.failure
    }
    #else
    Terminal.error("the service is a macOS launchd agent.")
    throw ExitCode.failure
    #endif
}
