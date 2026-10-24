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

    public init(
        id: String, title: String, subtitle: String = "", icon: ResultIcon = .none,
        score: Double, titleMatches: [Int] = [], action: ResultAction,
        alternateAction: ResultAction? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.score = score
        self.titleMatches = titleMatches
        self.action = action
        self.alternateAction = alternateAction
    }
}

public enum ResultIcon: Sendable, Hashable {
    case none
    /// The Finder icon of a file or bundle.
    case file(URL)
    /// An SF Symbol name.
    case symbol(String)
}

public enum ResultAction: Sendable, Equatable {
    case open(URL)
    case revealInFinder(URL)
    case copyToClipboard(String)
    case command(LauncherCommand)
}

/// Actions handled by the launcher itself rather than the system.
public enum LauncherCommand: Sendable, Equatable {}
