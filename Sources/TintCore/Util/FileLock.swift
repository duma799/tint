import Foundation

/// An exclusive lock shared between processes (`flock`), so the login
/// service, `tint apply` and the app never write a theme at the same time —
/// which would mix two schemes' files, or lose an edit to an editor's settings.
/// The lock goes away with the process, so a crash can't leave it stuck.
public enum FileLock {
    public enum Failure: Error, CustomStringConvertible {
        case open(String, String)
        case busy(String, TimeInterval)

        public var description: String {
            switch self {
            case .open(let path, let why): "couldn't open the lock file \(path): \(why)"
            case .busy(let path, let timeout): "another tint is still applying a theme after \(Int(timeout)) s (lock: \(path))"
            }
        }
    }

    /// Runs `body` holding the lock at `path`, waiting up to `timeout` for it.
    public static func withLock<T>(_ path: String, timeout: TimeInterval = 60, _ body: () throws -> T) throws -> T {
        // Close-on-exec: reload scripts tint starts (and may leave running)
        // must not inherit the lock and keep holding it.
        let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
        guard fd >= 0 else { throw Failure.open(path, String(cString: strerror(errno))) }
        defer { close(fd) } // closing releases the lock

        let deadline = Date().addingTimeInterval(timeout)
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            let error = errno
            guard error == EWOULDBLOCK || error == EINTR else { throw Failure.open(path, String(cString: strerror(error))) }
            guard Date() < deadline else { throw Failure.busy(path, timeout) }
            usleep(50_000)
        }
        return try body()
    }
}
