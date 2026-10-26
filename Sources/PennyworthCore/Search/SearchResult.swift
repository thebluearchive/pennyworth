import Foundation

public struct SearchResult: Identifiable, Sendable, Equatable {
    /// Stable identity across searches, e.g. `app:/Applications/Safari.app`.
    /// Also the key used to learn which results the user picks.
    public var id: String
    public var title: String
    public var subtitle: String
    public var icon: ResultIcon
    public var score: Double
    /// Character offsets into `title` to highlight as matching the query.
    public var titleMatches: [Int]
    /// Performed on ↩.
    public var action: ResultAction
    /// Performed on ⌘↩, when present.
    public var alternateAction: ResultAction?
    /// Query text to fill in on ⇥.
    public var autocomplete: String?
    /// Whether picking this result should teach the ranking (false for one-off answers
    /// like calculations).
    public var isLearnable: Bool

    public init(
        id: String, title: String, subtitle: String = "", icon: ResultIcon = .none,
        score: Double, titleMatches: [Int] = [], action: ResultAction,
        alternateAction: ResultAction? = nil, autocomplete: String? = nil, isLearnable: Bool = true
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.score = score
        self.titleMatches = titleMatches
        self.action = action
        self.alternateAction = alternateAction
        self.autocomplete = autocomplete
        self.isLearnable = isLearnable
    }
}

public enum ResultIcon: Sendable, Hashable {
    case none
    /// The Finder icon of a file or bundle.
    case file(URL)
    /// An SF Symbol name.
    case symbol(String)
    /// Color swatches previewing a theme; the first is the backdrop.
    case palette([RGBAColor])
}

public enum ResultAction: Sendable, Equatable {
    case open(URL)
    /// Open a URL or file in a specific app, e.g. a bookmark in the browser it came from.
    case openWith(URL, application: URL)
    case revealInFinder(URL)
    case copyToClipboard(String)
    /// Run a shell command in a new window of a terminal app.
    case runInTerminal(String, terminal: URL)
    /// Replace the query, keeping the launcher open.
    case autocomplete(String)
    case command(LauncherCommand)
}

/// Actions handled by the launcher itself rather than the system.
public enum LauncherCommand: Sendable, Equatable {
    case setTheme(id: String)
}
