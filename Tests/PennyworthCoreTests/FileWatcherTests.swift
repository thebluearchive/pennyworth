import Foundation
import Testing
@testable import PennyworthCore

@Suite struct FileWatcherTests {
    @Test func reportsChangesInsideWatchedFolders() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pennyworth-watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("nested"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let (changes, continuation) = AsyncStream.makeStream(of: Void.self)
        let watcher = FileWatcher(
            paths: [directory.path], latency: 0.05, queue: DispatchQueue(label: "test")
        ) {
            continuation.yield()
        }
        #expect(watcher.isWatching)

        // FSEvents needs a moment to start delivering.
        try await Task.sleep(for: .milliseconds(300))
        try "x".write(to: directory.appendingPathComponent("nested/file.json"), atomically: true, encoding: .utf8)

        let received = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await _ in changes { return true }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            continuation.finish()
            return first
        }
        #expect(received)
        withExtendedLifetime(watcher) {}
    }

    @Test func ignoresMissingPaths() {
        let watcher = FileWatcher(paths: ["/nonexistent-\(UUID())"]) {}
        #expect(!watcher.isWatching)
    }
}
