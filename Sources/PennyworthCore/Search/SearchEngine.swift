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

    /// The rest of the query if it starts with `keyword` and a space (`b vento` → `vento`).
    /// The space is required, so typing just `b` still searches normally.
    public func removingKeyword(_ keyword: String) -> SearchQuery? {
        let typed = raw.drop(while: \.isWhitespace)
        let prefix = keyword + " "
        guard typed.count >= prefix.count,
              typed.prefix(prefix.count).lowercased() == prefix.lowercased() else { return nil }
        return SearchQuery(String(typed.dropFirst(prefix.count)))
    }
}

/// A source of results, e.g. installed applications.
public protocol SearchProvider: Sendable {
    /// When set, the provider is only searched for queries starting with this word, and
    /// then exclusively: `search` receives the rest of the query and other providers are skipped.
    var keyword: String? { get }

    func search(_ query: SearchQuery) async -> [SearchResult]

    /// For keyword providers: results to mix into ordinary queries, such as a hint that
    /// offers the keyword.
    func suggestions(for query: SearchQuery) async -> [SearchResult]
}

extension SearchProvider {
    public var keyword: String? { nil }

    public func suggestions(for query: SearchQuery) async -> [SearchResult] { [] }
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

        // A keyword claims the query for its provider alone.
        let claimed = providers.compactMap { provider in
            provider.keyword.flatMap(query.removingKeyword).map { (provider, $0) }
        }

        let results = await withTaskGroup(of: [SearchResult].self) { group in
            if claimed.isEmpty {
                for provider in providers {
                    group.addTask {
                        provider.keyword == nil
                            ? await provider.search(query) : await provider.suggestions(for: query)
                    }
                }
            } else {
                for (provider, rest) in claimed {
                    group.addTask { await provider.search(rest) }
                }
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
