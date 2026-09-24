import Foundation

/// The outcome of running an external program.
public struct ProcessResult: Sendable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String

    public var succeeded: Bool { exitCode == 0 }
}

public enum ProcessError: Error, CustomStringConvertible {
    case notFound(String)
    case timedOut(String)

    public var description: String {
        switch self {
        case .notFound(let program): "\(program) not found"
        case .timedOut(let program): "\(program) did not finish in time"
        }
    }
}

/// Runs small helper programs (launchctl, pgrep, sketchybar…).
public enum ProcessRunner {
    /// Runs and captures output.
    public static func run(_ program: String, _ arguments: [String], timeout: TimeInterval = 10) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: try resolve(program))
        process.arguments = arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err

        // Read both streams while it runs, or a chatty program can fill a
        // pipe and wait forever for us to empty it.
        let outData = Collected(), errData = Collected()
        let reads = DispatchGroup()
        for (pipe, sink) in [(out, outData), (err, errData)] {
            reads.enter()
            DispatchQueue.global().async {
                sink.data = pipe.fileHandleForReading.readDataToEndOfFile()
                reads.leave()
            }
        }

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            throw ProcessError.timedOut(program)
        }
        reads.wait()

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: outData.data, as: UTF8.self).trimmingWhitespace(),
            stderr: String(decoding: errData.data, as: UTF8.self).trimmingWhitespace())
    }

    /// Runs without capturing output — for scripts that may start background
    /// processes, whose open pipes would otherwise keep tint waiting.
    /// - Returns: the exit code, or nil if it was still running at the timeout.
    public static func runDetached(
        _ program: String, _ arguments: [String] = [], timeout: TimeInterval, environment: [String: String] = [:]
    ) throws -> Int32? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: try resolve(program))
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        return finished.wait(timeout: .now() + timeout) == .timedOut ? nil : process.terminationStatus
    }

    /// True if a process with exactly this name is running (`pgrep -x`).
    public static func isRunning(_ name: String) -> Bool {
        (try? run("pgrep", ["-x", name]))?.succeeded ?? false
    }

    private static func resolve(_ program: String) throws -> String {
        if program.contains("/") { return program }
        // /usr/bin and /bin first: launchd gives agents a short PATH.
        let path = (ProcessInfo.processInfo.environment["PATH"] ?? "") + ":/usr/bin:/bin:/usr/sbin:/sbin"
        guard let found = TintPaths.findOnPath(program, path: path) else { throw ProcessError.notFound(program) }
        return found
    }

    private final class Collected: @unchecked Sendable {
        var data = Data()
    }
}
