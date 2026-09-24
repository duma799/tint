import Foundation

#if os(macOS)
import CoreServices
#endif

/// Watches folders whose changes mean "the wallpaper may have changed",
/// waits until a burst of file events has been quiet for a moment, then asks
/// `locate` what the wallpaper is now — and reports it only if it actually
/// changed. Changing the wallpaper writes several files in quick succession;
/// without the wait, every write would re-theme everything.
public final class WallpaperWatcher: @unchecked Sendable {
    public typealias Locate = @Sendable () -> String?

    private let locate: Locate
    private let directories: [String]
    private let settle: TimeInterval
    private let queue = DispatchQueue(label: "tint.watcher")
    private var pending: DispatchWorkItem?
    private var last: String?
    private var poll: DispatchSourceTimer?
    #if os(macOS)
    private var stream: FSEventStreamRef?
    #endif

    /// Called on a background queue with each new wallpaper.
    public var onChange: (@Sendable (String) -> Void)?

    /// Low-level detail (file events, fallbacks) for `--verbose`.
    public var onTrace: (@Sendable (String) -> Void)?

    public init(directories: [String], settle: TimeInterval = 0.4, locate: @escaping Locate) {
        self.directories = directories
        self.settle = settle
        self.locate = locate
    }

    deinit { stop() }

    public func start() {
        queue.sync { last = locate() }
        let existing = directories.filter(TintPaths.isDirectory)
        for missing in directories where !existing.contains(missing) {
            onTrace?("\(missing) not found — not watching it")
        }

        #if os(macOS)
        if !existing.isEmpty {
            startEventStream(existing)
            return
        }
        #endif

        // Better slow than blind: nothing to watch (or no FSEvents), so ask every 2 s.
        onTrace?("checking every 2 s instead")
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in self?.check() }
        timer.resume()
        poll = timer
    }

    public func stop() {
        poll?.cancel()
        poll = nil
        #if os(macOS)
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        #endif
    }

    /// (Re)starts the countdown; only the last event in a burst leads to a check.
    public func trigger() {
        queue.async { [self] in
            pending?.cancel()
            let item = DispatchWorkItem { [weak self] in self?.check() }
            pending = item
            queue.asyncAfter(deadline: .now() + settle, execute: item)
        }
    }

    /// Re-reads the wallpaper and reports it if it moved on. Runs on `queue`.
    func check() {
        guard let current = locate(), current != last else { return }
        last = current
        onChange?(current)
    }

    /// For tests: runs `check` on the watcher's queue and waits.
    func checkNow() { queue.sync { check() } }

    #if os(macOS)
    private func startEventStream(_ paths: [String]) {
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<WallpaperWatcher>.fromOpaque(info).takeUnretainedValue()
            if let trace = watcher.onTrace, let names = unsafeBitCast(paths, to: NSArray.self) as? [String] {
                for name in names.prefix(count) { trace("changed: \(name)") }
            }
            watcher.trigger()
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.1, flags)
        else {
            onTrace?("couldn't start watching; checking every 2 s instead")
            return
        }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
        for path in paths { onTrace?("watching \(path)") }
    }
    #endif
}
