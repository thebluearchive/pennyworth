import Foundation

public struct SearchQuery: Sendable {
    public let raw: String
    /// `raw` with surrounding whitespace removed.
    public let text: String
    public let fuzzy: FuzzyQuery

    public init(_ raw: String) {
        self.raw = raw
        text = raw.trimmingCharacters(in: .whitespaces)
        fuzzy = FuzzyQuery(text)
    }
}

/// A source of results, e.g. installed applications.
public protocol SearchProvider: Sendable {
    func search(_ query: SearchQuery) async -> [SearchResult]
}

/// Fans a query out to every provider and merges the results by score.
public struct SearchEngine: Sendable {
    public var providers: [any SearchProvider]

    public init(providers: [any SearchProvider]) {
        self.providers = providers
    }

    public func search(_ raw: String, limit: Int = 50) async -> [SearchResult] {
        let query = SearchQuery(raw)
        guard !query.text.isEmpty else { return [] }

        let results = await withTaskGroup(of: [SearchResult].self) { group in
            for provider in providers {
                group.addTask { await provider.search(query) }
            }
            return await group.reduce(into: []) { $0 += $1 }
        }
        guard !Task.isCancelled else { return [] }
        return Array(results.sorted(by: Self.ranksBefore).prefix(limit))
    }

    static func ranksBefore(_ a: SearchResult, _ b: SearchResult) -> Bool {
        if a.score != b.score { return a.score > b.score }
        if a.title.count != b.title.count { return a.title.count < b.title.count }
        return a.title.localizedStandardCompare(b.title) == .orderedAscending
    }
}
