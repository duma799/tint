import Foundation

public struct ServiceStatus: Sendable {
    public var installed: Bool
    public var loaded: Bool
    public var pid: Int?
    public var programArguments: [String]

    public var running: Bool { pid != nil }
}

/// Runs `tint watch` at login, as a launchd user agent: a plist in
/// `~/Library/LaunchAgents` that launchd starts when you log in and restarts
/// if it crashes. Output goes to `~/Library/Logs/tint.log`.
public enum LaunchAgent {
    public static let label = "io.github.duma799.tint"

    public static var plistPath: String { TintPaths.home + "/Library/LaunchAgents/\(label).plist" }

    public enum Failure: Error, CustomStringConvertible {
        case launchctl(String)

        public var description: String {
            switch self { case .launchctl(let why): "launchctl: \(why)" }
        }
    }

    /// launchd starts agents with a bare PATH (/usr/bin:/bin:/usr/sbin:/sbin),
    /// where sketchybar, borders and most hooks' tools aren't. So the agent
    /// gets the PATH of the shell that installed it, plus Homebrew's folders.
    public static func servicePath(_ current: String?) -> String {
        let wanted = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        var seen = Set<String>()
        let parts = (current ?? "").split(separator: ":").map(String.init) + wanted
        return parts.filter { seen.insert($0).inserted }.joined(separator: ":")
    }

    /// The agent's plist. Pure, so it can be tested anywhere.
    public static func plist(programArguments: [String], environment: [String: String], log: String) -> String {
        func string(_ value: String) -> String { "<string>\(xml(value))</string>" }

        var s = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          \(string(label))
          <key>ProgramArguments</key>
          <array>

        """
        for argument in programArguments { s += "    \(string(argument))\n" }
        s += "  </array>\n  <key>EnvironmentVariables</key>\n  <dict>\n"
        for (key, value) in environment.sorted(by: { $0.key < $1.key }) {
            s += "    <key>\(xml(key))</key>\n    \(string(value))\n"
        }
        s += "  </dict>\n  <key>RunAtLoad</key>\n  <true/>\n"
        // Restart after a crash, but not after a clean exit (e.g. `tint service uninstall`).
        s += "  <key>KeepAlive</key>\n  <dict>\n    <key>SuccessfulExit</key>\n    <false/>\n  </dict>\n"
        s += "  <key>StandardOutPath</key>\n  \(string(log))\n"
        s += "  <key>StandardErrorPath</key>\n  \(string(log))\n"
        s += "</dict>\n</plist>\n"
        return s
    }

    /// How to start this tint: the `tint` on the PATH if it is this same
    /// program (a Homebrew link survives upgrades; the file it points to
    /// doesn't), else this program's own path.
    public static func tintCommand(executable: String) -> [String] {
        let me = TintPaths.realPath(executable)
        if let onPath = TintPaths.findOnPath("tint"), TintPaths.realPath(onPath) == me {
            return [onPath]
        }
        return [me]
    }

    public static func install(programArguments: [String]) throws {
        let environment = ["PATH": servicePath(ProcessInfo.processInfo.environment["PATH"])]
        let fm = FileManager.default
        try fm.createDirectory(atPath: (plistPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: (TintPaths.log as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try PywalWriter.atomicWrite(plist(programArguments: programArguments, environment: environment, log: TintPaths.log), to: plistPath)

        // Unload any older copy first; "not loaded" is fine.
        _ = try? launchctl("bootout", target)
        let load = try launchctl("bootstrap", domain, plistPath)
        guard load.succeeded else { throw Failure.launchctl(load.stderr) }
    }

    /// - Returns: whether it was installed.
    @discardableResult
    public static func uninstall() throws -> Bool {
        let existed = TintPaths.exists(plistPath)
        _ = try? launchctl("bootout", target)
        if existed { try FileManager.default.removeItem(atPath: plistPath) }
        return existed
    }

    public static func restart() throws {
        let result = try launchctl("kickstart", "-k", target)
        guard result.succeeded else { throw Failure.launchctl(result.stderr) }
    }

    public static func status() -> ServiceStatus {
        let installed = TintPaths.exists(plistPath)
        let program = installed ? (FileManager.default.contents(atPath: plistPath).map(programArguments) ?? []) : []
        guard let print = try? launchctl("print", target), print.succeeded else {
            return ServiceStatus(installed: installed, loaded: false, pid: nil, programArguments: program)
        }
        return ServiceStatus(installed: installed, loaded: true, pid: pid(fromLaunchctlPrint: print.stdout), programArguments: program)
    }

    /// The `pid = 123` line of `launchctl print`; absent when it isn't running.
    public static func pid(fromLaunchctlPrint output: String) -> Int? {
        for line in output.split(separator: "\n") {
            let parts = String(line).trimmingWhitespace().components(separatedBy: " = ")
            if parts.count == 2, parts[0] == "pid", let pid = Int(parts[1]) { return pid }
        }
        return nil
    }

    public static func programArguments(fromPlist data: Data) -> [String] {
        let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        return plist?["ProgramArguments"] as? [String] ?? []
    }

    private static var domain: String { "gui/\(getuid())" }
    private static var target: String { "\(domain)/\(label)" }

    private static func launchctl(_ arguments: String...) throws -> ProcessResult {
        try ProcessRunner.run("launchctl", arguments)
    }

    private static func xml(_ value: String) -> String {
        value.replacingAll("&", with: "&amp;").replacingAll("<", with: "&lt;").replacingAll(">", with: "&gt;")
            .replacingAll("\"", with: "&quot;").replacingAll("'", with: "&apos;")
    }
}
