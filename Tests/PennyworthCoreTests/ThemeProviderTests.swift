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
        let results = await search("theme ")
        #expect(results.map(\.title) == Theme.builtIn.map(\.name))
        #expect(results.first?.subtitle.hasPrefix("✓ Current") == true)
        #expect(results[1].action == .command(.setTheme(id: "tokyo-night-storm")))
    }

    @Test func currentThemeIsListedFirst() async {
        provider.update(themes: Theme.builtIn, currentID: "nord")
        let titles = await search("theme ").map(\.title)
        #expect(titles.first == "Nord")
        #expect(Array(titles.dropFirst()) == Theme.builtIn.map(\.name).filter { $0 != "Nord" })
    }

    @Test func textAfterTheKeywordFilters() async {
        let results = await search("Theme  sto")
        #expect(results.map(\.title) == ["Tokyo Night Storm"])
        #expect(results.first?.titleMatches == [12, 13, 14])
    }

    @Test func prefixOffersAHintThatCompletesTheKeyword() async {
        for text in ["them", "theme", "change th"] {
            let results = await search(text)
            #expect(results.count == 1, "\(text)")
            #expect(results.first?.action == .autocomplete("theme "), "\(text)")
            #expect(results.first?.subtitle.contains("Tokyo Night") == true, "\(text)")
        }
    }

    @Test func unrelatedQueriesReturnNothing() async {
        #expect(await search("safari").isEmpty)
        #expect(await search("t").isEmpty)
        #expect(await search("themes").isEmpty)
    }

    @Test func keywordHidesOtherProviders() async throws {
        let fake = try FakeApplications()
        try fake.app("Theme Park.app")
        let apps = ApplicationProvider(scanner: ApplicationScanner(locations: [.init(fake.root, depth: 1)]))
        apps.reload()
        let engine = SearchEngine(providers: [apps, provider])

        // Without the space it's an ordinary query; with it, only themes are searched.
        #expect(await engine.search("theme").map(\.title) == ["Change Theme", "Theme Park"])
        #expect(await engine.search("theme ").map(\.title) == Theme.builtIn.map(\.name))
        #expect(await engine.search("theme park").isEmpty)
    }
}
