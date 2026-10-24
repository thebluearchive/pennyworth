import Foundation
import Testing
@testable import PennyworthCore

@Suite struct ThemeProviderTests {
    let provider: ThemeProvider

    init() {
        provider = ThemeProvider()
        provider.update(themes: Theme.builtIn, currentID: "tokyo-night")
    }

    private func search(_ text: String) async -> [SearchResult] {
        await SearchEngine(providers: [provider]).search(text)
    }

    @Test func keywordListsEveryThemeInLibraryOrder() async {
        let results = await search("theme")
        #expect(results.map(\.title) == Theme.builtIn.map(\.name))
        #expect(results.first?.subtitle.hasPrefix("✓ Current") == true)
        #expect(results[1].action == .command(.setTheme(id: "tokyo-night-storm")))
    }

    @Test func textAfterTheKeywordFilters() async {
        let results = await search("Theme  sto")
        #expect(results.map(\.title) == ["Tokyo Night Storm"])
        #expect(results.first?.titleMatches == [12, 13, 14])
    }

    @Test func prefixOffersAHintThatCompletesTheKeyword() async {
        let results = await search("them")
        #expect(results.count == 1)
        #expect(results.first?.action == .autocomplete("theme "))
        #expect(results.first?.subtitle.contains("Tokyo Night") == true)
    }

    @Test func unrelatedQueriesReturnNothing() async {
        #expect(await search("safari").isEmpty)
        #expect(await search("t").isEmpty)
        #expect(await search("themes").isEmpty)
    }

    @Test func outranksApplications() async throws {
        let results = await search("theme")
        #expect(results.allSatisfy { $0.score > 900 })
    }
}
