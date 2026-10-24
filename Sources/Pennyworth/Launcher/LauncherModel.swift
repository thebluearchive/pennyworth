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
    var theme: Theme
    var maxVisibleResults: Int
    /// Incremented to ask the search field to take keyboard focus.
    private(set) var focusRequest = 0

    @ObservationIgnored var engine: SearchEngine
    /// Called after `results` changes, so the window can resize.
    @ObservationIgnored var onResultsChanged: (() -> Void)?
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init(engine: SearchEngine, theme: Theme, maxVisibleResults: Int) {
        self.engine = engine
        self.theme = theme
        self.maxVisibleResults = maxVisibleResults
    }

    var selectedResult: SearchResult? {
        results.indices.contains(selection) ? results[selection] : nil
    }

    func setQuery(_ query: String) {
        self.query = query
        searchTask?.cancel()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            show([])
            return
        }
        let engine = engine
        searchTask = Task { [weak self] in
            let results = await engine.search(query)
            guard !Task.isCancelled else { return }
            self?.show(results)
        }
    }

    /// Re-runs the current query, e.g. after the app index or themes change.
    func refresh() {
        setQuery(query)
    }

    func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        selection = min(max(selection + offset, 0), results.count - 1)
    }

    func requestFocus() {
        focusRequest += 1
    }

    func reset() {
        searchTask?.cancel()
        query = ""
        show([])
    }

    private func show(_ results: [SearchResult]) {
        self.results = results
        selection = 0
        onResultsChanged?()
    }
}
