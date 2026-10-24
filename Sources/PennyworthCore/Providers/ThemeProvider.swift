import Foundation
import os

/// Lists themes for the `theme` keyword: `theme ` shows all, `theme sto` filters.
/// Typing `them`, `theme` or "change theme" offers a hint that completes the keyword.
public final class ThemeProvider: SearchProvider {
    public static let keyword = "theme"
    public var keyword: String? { Self.keyword }

    private struct State: Sendable {
        var themes: [Theme] = []
        var currentID = ""
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private static let hint = MatchCandidate("Change Theme")
    private static let keywordCandidate = MatchCandidate(keyword)

    public init() {}

    public func update(themes: [Theme], currentID: String) {
        state.withLock { $0 = State(themes: themes, currentID: currentID) }
    }

    /// `query` is what follows the keyword.
    public func search(_ query: SearchQuery) async -> [SearchResult] {
        let state = state.withLock { $0 }
        return state.themes.enumerated().compactMap { index, theme in
            // Unfiltered, the current theme comes first (so it's selected and previewing
            // doesn't change anything) and the rest keep library order.
            let isCurrent = theme.id == state.currentID
            var score = isCurrent ? 2 : 1 - Double(index) * 0.001
            var matches: [Int] = []
            if !query.fuzzy.isEmpty {
                guard let match = FuzzyMatcher.match(query.fuzzy, in: MatchCandidate(theme.name)) else {
                    return nil
                }
                score = match.score
                matches = match.positions
            }
            return SearchResult(
                id: "theme:\(theme.id)",
                title: theme.name,
                subtitle: Self.subtitle(for: theme, isCurrent: isCurrent),
                icon: .palette(theme.colors.swatches),
                score: score,
                titleMatches: matches,
                action: .command(.setTheme(id: theme.id)),
                autocomplete: "\(Self.keyword) \(theme.name)")
        }
    }

    public func suggestions(for query: SearchQuery) async -> [SearchResult] {
        let state = state.withLock { $0 }
        let current = state.themes.first { $0.id == state.currentID }
        let matches = [Self.keywordCandidate, Self.hint].compactMap {
            FuzzyMatcher.match(query.fuzzy, in: $0)
        }
        guard query.text.count >= 2, let best = matches.max(by: { $0.score < $1.score }) else {
            return []
        }
        let completion = Self.keyword + " "
        return [SearchResult(
            id: "theme:browse",
            title: "Change Theme",
            subtitle: current.map { "Current: \($0.name) · ↩ to browse themes" } ?? "Browse themes",
            icon: .symbol("paintpalette"),
            score: best.score,
            action: .autocomplete(completion),
            autocomplete: completion)]
    }

    private static func subtitle(for theme: Theme, isCurrent: Bool) -> String {
        var parts = [isCurrent ? "✓ Current" : nil, theme.appearance == .dark ? "Dark" : "Light"]
        if let source = theme.source {
            parts.append((source.path as NSString).abbreviatingWithTildeInPath)
        } else {
            parts.append("Built-in")
        }
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
}

extension Theme.Colors {
    /// Representative colors for a small preview: background first.
    public var swatches: [RGBAColor] {
        [background, border, accent, match, text]
    }
}
