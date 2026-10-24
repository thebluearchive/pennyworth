import CoreServices
import Foundation

/// Calls `handler` when anything inside the given folders changes. Events are
/// coalesced over `latency` seconds. Stops when released.
public final class FileWatcher {
    private var stream: FSEventStreamRef?
    private let handler: @Sendable () -> Void

    /// Paths that don't exist yet are ignored.
    public init(
        paths: [String], latency: TimeInterval = 0.5, queue: DispatchQueue = .main,
        handler: @escaping @Sendable () -> Void
    ) {
        self.handler = handler
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !existing.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue().handler()
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context, existing as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone))
        else { return }

        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    public var isWatching: Bool { stream != nil }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}

extension ApplicationScanner {
    /// Folders whose changes may add or remove applications.
    public var watchedPaths: [String] {
        locations.map(\.url.path)
    }
}
