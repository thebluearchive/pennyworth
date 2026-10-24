import Foundation
import os

/// Searches Firefox bookmarks by title, and less strongly by URL, tags, keyword and folder.
public final class FirefoxBookmarkProvider: SearchProvider {
    /// Bookmarks rank a little below applications with an equally good match.
    static let weight = 0.9
    /// Matches on anything but the title count for less.
    static let secondaryWeight = 0.8
    /// Page titles and URLs are long, so demand tighter matches than for app names.
    static let minimumScorePerCharacter = 0.6

    private struct Entry: Sendable {
        let bookmark: Bookmark
        let title: MatchCandidate
        let keyword: String?
        /// URL, tags, keyword and folder.
        let secondary: [MatchCandidate]
    }

    private struct State: Sendable {
        var entries: [Entry] = []
        var bookmarks: [Bookmark] = []
        /// Sizes and dates of the databases last read, to skip unchanged reloads.
        var fingerprint: [String] = []
        var problem: String?
    }

    private let directory: URL
    private let icon: ResultIcon
    private let browser: URL?
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// - Parameters:
    ///   - icon: Shown next to every bookmark, e.g. Firefox's app icon.
    ///   - browser: The app to open bookmarks in; `nil` uses the default browser.
    public init(
        directory: URL = FirefoxBookmarks.defaultDirectory, icon: ResultIcon = .symbol("bookmark"),
        browser: URL? = nil
    ) {
        self.directory = directory
        self.icon = icon
        self.browser = browser
    }

    public var bookmarks: [Bookmark] { state.withLock { $0.bookmarks } }

    /// Why the last reload failed, if it did.
    public var problem: String? { state.withLock { $0.problem } }

    /// Re-reads bookmarks if any profile's database changed since the last read.
    /// Cheap when nothing changed. Returns whether the bookmarks changed.
    @discardableResult
    public func reloadIfChanged() -> Bool {
        let profiles = FirefoxBookmarks.profiles(in: directory)
        let fingerprint = profiles.flatMap { profile in
            ["places.sqlite", "places.sqlite-wal"].map { name in
                let path = profile.appendingPathComponent(name).path
                let attributes = try? FileManager.default.attributesOfItem(atPath: path)
                let size = attributes?[.size] as? Int ?? -1
                let date = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
                return "\(path):\(size):\(date)"
            }
        }
        guard fingerprint != state.withLock({ $0.fingerprint }) else { return false }

        var seen = Set<URL>()
        var bookmarks: [Bookmark] = []
        for profile in profiles {
            do {
                for bookmark in try FirefoxBookmarks.read(profile: profile)
                where seen.insert(bookmark.url).inserted {
                    bookmarks.append(bookmark)
                }
            } catch {
                // Keep what we had; the unchanged fingerprint means we retry next time.
                state.withLock { $0.problem = "Firefox bookmarks (\(profile.lastPathComponent)): \(error)" }
                return false
            }
        }

        let entries = bookmarks.map { bookmark in
            Entry(
                bookmark: bookmark, title: MatchCandidate(bookmark.title),
                keyword: bookmark.keyword?.lowercased(),
                secondary: ([Self.displayURL(bookmark.url)] + bookmark.tags
                    + [bookmark.keyword].compactMap { $0 } + bookmark.folders.suffix(1))
                    .map(MatchCandidate.init))
        }
        let fresh = State(entries: entries, bookmarks: bookmarks, fingerprint: fingerprint, problem: nil)
        return state.withLock { state in
            let changed = state.bookmarks != fresh.bookmarks
            state = fresh
            return changed
        }
    }

    public func search(_ query: SearchQuery) async -> [SearchResult] {
        guard !query.fuzzy.isEmpty else { return [] }
        let entries = state.withLock { $0.entries }

        return entries.compactMap { entry -> SearchResult? in
            func match(_ candidate: MatchCandidate) -> FuzzyMatch? {
                FuzzyMatcher.match(query.fuzzy, in: candidate, minimumScorePerCharacter: Self.minimumScorePerCharacter)
            }
            let titleMatch = match(entry.title)
            var score = titleMatch?.score ?? -.infinity
            // Typing a bookmark's keyword is a deliberate shortcut, so an exact one wins outright.
            if let keyword = entry.keyword, keyword == query.text.lowercased() {
                score = FuzzyMatcher.Score.exact
            }
            // Cap other fields below a title prefix match (about 1 per character), so an exact
            // folder name doesn't outrank every title that starts with the query.
            let cap = Double(query.text.count)
            for candidate in entry.secondary {
                if let secondaryMatch = match(candidate) {
                    score = max(score, min(secondaryMatch.score, cap) * Self.secondaryWeight)
                }
            }
            guard score > -.infinity else { return nil }

            let bookmark = entry.bookmark
            var subtitle = Self.displayURL(bookmark.url)
            if !bookmark.folders.isEmpty {
                subtitle += "  ·  " + bookmark.folders.joined(separator: " › ")
            }
            return SearchResult(
                id: "firefox:\(bookmark.url.absoluteString)",
                title: bookmark.title,
                subtitle: subtitle,
                icon: icon,
                score: score * Self.weight,
                // Highlight only when the title is what matched best.
                titleMatches: titleMatch.flatMap { $0.score >= score ? $0.positions : nil } ?? [],
                action: browser.map { .openWith(bookmark.url, application: $0) } ?? .open(bookmark.url),
                alternateAction: .copyToClipboard(bookmark.url.absoluteString),
                autocomplete: bookmark.title)
        }
    }

    /// `https://www.example.com/path/` → `example.com/path`
    static func displayURL(_ url: URL) -> String {
        var text = url.absoluteString
        for prefix in ["https://", "http://"] where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
        }
        if text.hasPrefix("www.") { text.removeFirst(4) }
        if text.hasSuffix("/") { text.removeLast() }
        return text
    }
}
