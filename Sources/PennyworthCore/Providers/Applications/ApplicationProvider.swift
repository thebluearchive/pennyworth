import Foundation
import os

/// Searches installed applications by name.
public final class ApplicationProvider: SearchProvider {
    private struct Entry: Sendable {
        let application: Application
        /// Primary name first, then alternates.
        let candidates: [MatchCandidate]
    }

    private let scanner: ApplicationScanner
    private let entries = OSAllocatedUnfairLock<[Entry]>(initialState: [])

    public init(scanner: ApplicationScanner = ApplicationScanner()) {
        self.scanner = scanner
    }

    public var applications: [Application] {
        entries.withLock { $0.map(\.application) }
    }

    /// Rescans the filesystem. Safe to call from any thread.
    /// Returns whether the set of applications changed.
    @discardableResult
    public func reload() -> Bool {
        let scanned = scanner.scan()
        let previous = applications
        guard scanned != previous else { return false }
        let fresh = scanned.map { app in
            Entry(application: app,
                  candidates: ([app.name] + app.alternateNames).map(MatchCandidate.init))
        }
        entries.withLock { $0 = fresh }
        return true
    }

    public func search(_ query: SearchQuery) async -> [SearchResult] {
        guard !query.fuzzy.isEmpty else { return [] }
        let snapshot = entries.withLock { $0 }

        return snapshot.compactMap { entry -> SearchResult? in
            var best: (match: FuzzyMatch, isPrimary: Bool)?
            for (index, candidate) in entry.candidates.enumerated() {
                guard let match = FuzzyMatcher.match(query.fuzzy, in: candidate) else { continue }
                if best == nil || match.score > best!.match.score {
                    best = (match, index == 0)
                }
            }
            guard let best else { return nil }

            let app = entry.application
            return SearchResult(
                id: "app:\(app.url.path)",
                title: app.name,
                subtitle: (app.url.path as NSString).abbreviatingWithTildeInPath,
                icon: .file(app.url),
                score: best.match.score,
                titleMatches: best.isPrimary ? best.match.positions : [],
                action: .open(app.url),
                alternateAction: .revealInFinder(app.url),
                autocomplete: app.name)
        }
    }
}
