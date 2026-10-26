import Foundation

/// Runs the shell command typed after `>` (`> python3`) in a new terminal window.
public struct TerminalProvider: SearchProvider {
    public let keyword: String? = ">"
    private let terminal: URL
    private let terminalName: String

    /// - Parameter terminal: The app to run commands in, e.g. Terminal or Ghostty.
    public init(terminal: URL) {
        self.terminal = terminal
        terminalName = terminal.deletingPathExtension().lastPathComponent
    }

    private static let hintCandidates = ["terminal", "shell", "command"].map(MatchCandidate.init)

    /// `query` is what follows the keyword.
    public func search(_ query: SearchQuery) async -> [SearchResult] {
        guard !query.text.isEmpty else {
            return [hint(subtitle: "Type a command · ↩ runs it", score: 0)]
        }
        return [SearchResult(
            id: "terminal:run", title: query.text, subtitle: "Run in \(terminalName)",
            icon: .file(terminal), score: 0,
            action: .runInTerminal(query.text, terminal: terminal), isLearnable: false)]
    }

    /// Offers the keyword to `>` on its own, and below real matches to queries like "shell".
    public func suggestions(for query: SearchQuery) async -> [SearchResult] {
        let subtitle = "Type \u{201C}> \u{201D} then a command · ↩ to start"
        if query.text == keyword {
            return [hint(subtitle: subtitle, score: FuzzyMatcher.Score.exact)]
        }
        guard query.text.count >= 3,
              let match = Self.hintCandidates.compactMap({ FuzzyMatcher.match(query.fuzzy, in: $0) })
                .max(by: { $0.score < $1.score }) else { return [] }
        return [hint(subtitle: subtitle, score: match.score * 0.5)]
    }

    private func hint(subtitle: String, score: Double) -> SearchResult {
        SearchResult(
            id: "terminal:hint", title: "Run in \(terminalName)", subtitle: subtitle,
            icon: .file(terminal), score: score, action: .autocomplete("> "), autocomplete: "> ")
    }
}
