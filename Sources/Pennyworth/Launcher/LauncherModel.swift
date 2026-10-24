import Foundation
import Observation
import PennyworthCore

enum LauncherLayout {
    static let width: CGFloat = 680
    static let searchHeight: CGFloat = 60
    static let rowHeight: CGFloat = 48
    static let listPadding: CGFloat = 6

    static func height(resultCount: Int, maxVisible: Int) -> CGFloat {
        guard resultCount > 0 else { return searchHeight }
        let rows = CGFloat(min(resultCount, max(maxVisible, 1)))
        return searchHeight + 1 + rows * rowHeight + listPadding * 2
    }
}

@MainActor @Observable
final class LauncherModel {
    private(set) var query = ""
    private(set) var results: [SearchResult] = []
    private(set) var selection = 0
    /// The committed theme.
    var theme: Theme
    /// Shown instead of `theme` while a theme result is selected.
    var previewTheme: Theme?
    var maxVisibleResults: Int
    /// Incremented to ask the search field to take keyboard focus.
    private(set) var focusRequest = 0

    @ObservationIgnored var engine: SearchEngine
    /// Called after `results` or `selection` changes.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init(engine: SearchEngine, theme: Theme, maxVisibleResults: Int) {
        self.engine = engine
        self.theme = theme
        self.maxVisibleResults = maxVisibleResults
    }

    var activeTheme: Theme { previewTheme ?? theme }

    var selectedResult: SearchResult? {
        results.indices.contains(selection) ? results[selection] : nil
    }

    func setQuery(_ query: String) {
        search(query, keepingSelection: false)
    }

    /// Re-runs the current query, e.g. after the app index or themes change,
    /// keeping the same result selected if it's still there.
    func refresh() {
        search(query, keepingSelection: true)
    }

    func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        selection = min(max(selection + offset, 0), results.count - 1)
        onChange?()
    }

    func requestFocus() {
        focusRequest += 1
    }

    func reset() {
        searchTask?.cancel()
        query = ""
        show([], selecting: nil)
    }

    private func search(_ query: String, keepingSelection: Bool) {
        self.query = query
        searchTask?.cancel()
        let selectedID = keepingSelection ? selectedResult?.id : nil
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            show([], selecting: nil)
            return
        }
        let engine = engine
        searchTask = Task { [weak self] in
            let results = await engine.search(query)
            guard !Task.isCancelled else { return }
            self?.show(results, selecting: selectedID)
        }
    }

    private func show(_ results: [SearchResult], selecting id: String?) {
        self.results = results
        selection = id.flatMap { id in results.firstIndex { $0.id == id } } ?? 0
        onChange?()
    }
}
