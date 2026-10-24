import Foundation
import SQLite3
import Testing
@testable import PennyworthCore

/// A throwaway Firefox data folder with one profile and a minimal places.sqlite.
final class FakeFirefox {
    let directory: URL
    let profile: URL
    var database: URL { profile.appendingPathComponent("places.sqlite") }

    init(profileName: String = "abc.default-release") throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pennyworth-firefox-\(UUID().uuidString)")
        profile = directory.appendingPathComponent("Profiles/\(profileName)")
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)

        let db = try SQLiteDatabase(database, create: true)
        try db.execute("""
            PRAGMA journal_mode = WAL;
            CREATE TABLE moz_places (id INTEGER PRIMARY KEY, url TEXT, title TEXT);
            CREATE TABLE moz_bookmarks (
                id INTEGER PRIMARY KEY, type INTEGER, fk INTEGER, parent INTEGER,
                position INTEGER, title TEXT, guid TEXT);
            CREATE TABLE moz_keywords (id INTEGER PRIMARY KEY, keyword TEXT, place_id INTEGER);
            INSERT INTO moz_bookmarks (id, type, parent, title, guid) VALUES
                (1, 2, 0, '', 'root________'),
                (2, 2, 1, 'menu', 'menu________'),
                (3, 2, 1, 'toolbar', 'toolbar_____'),
                (4, 2, 1, 'tags', 'tags________'),
                (5, 2, 1, 'unfiled', 'unfiled_____'),
                (10, 2, 3, 'Dev', 'devfolder___'),
                (11, 2, 4, 'work', 'tagwork_____');
            """)
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    private var nextID: Int64 = 100

    /// Adds a bookmark in `folder` (a moz_bookmarks id) and returns its place id.
    @discardableResult
    func bookmark(_ url: String, title: String?, folder: Int64 = 3, placeTitle: String? = nil,
                  keyword: String? = nil, tags: [Int64] = []) throws -> Int64 {
        nextID += 1
        let place = nextID
        let db = try SQLiteDatabase(database)
        func quoted(_ text: String?) -> String {
            text.map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" } ?? "NULL"
        }
        try db.execute("""
            INSERT INTO moz_places (id, url, title) VALUES (\(place), \(quoted(url)), \(quoted(placeTitle)));
            INSERT INTO moz_bookmarks (type, fk, parent, position, title) VALUES (1, \(place), \(folder), \(place), \(quoted(title)));
            """)
        if let keyword {
            try db.execute("INSERT INTO moz_keywords (keyword, place_id) VALUES (\(quoted(keyword)), \(place))")
        }
        for tag in tags {
            try db.execute("INSERT INTO moz_bookmarks (type, fk, parent, position) VALUES (1, \(place), \(tag), 0)")
        }
        return place
    }

    func write(_ name: String, _ contents: String) throws {
        try contents.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
}

@Suite struct FirefoxBookmarksTests {
    let firefox: FakeFirefox

    init() throws {
        firefox = try FakeFirefox()
    }

    @Test func readsTitlesFoldersTagsAndKeywords() throws {
        try firefox.bookmark("https://github.com/", title: "GitHub", keyword: "gh", tags: [11])
        try firefox.bookmark("https://docs.swift.org/", title: "Swift Docs", folder: 10)
        try firefox.bookmark("https://example.com/untitled", title: nil, folder: 2, placeTitle: "Page Title")
        try firefox.bookmark("https://bare.example.org/", title: nil, folder: 5)

        let bookmarks = try FirefoxBookmarks.read(profile: firefox.profile)
        let byTitle = Dictionary(uniqueKeysWithValues: bookmarks.map { ($0.title, $0) })
        #expect(bookmarks.count == 4)

        let github = try #require(byTitle["GitHub"])
        #expect(github.folders == ["Bookmarks Toolbar"])
        #expect(github.tags == ["work"])
        #expect(github.keyword == "gh")
        #expect(byTitle["Swift Docs"]?.folders == ["Bookmarks Toolbar", "Dev"])
        #expect(byTitle["Page Title"]?.folders == ["Bookmarks Menu"])
        #expect(byTitle["bare.example.org"]?.folders == ["Other Bookmarks"])
    }

    @Test func skipsSmartAndScriptBookmarks() throws {
        try firefox.bookmark("place:sort=8&maxResults=10", title: "Most Visited")
        try firefox.bookmark("javascript:alert(1)", title: "Bookmarklet")
        try firefox.bookmark("https://kept.example/", title: "Kept")
        #expect(try FirefoxBookmarks.read(profile: firefox.profile).map(\.title) == ["Kept"])
    }

    @Test func readsWhileFirefoxHoldsAnExclusiveLock() throws {
        try firefox.bookmark("https://before.example/", title: "Before")
        // Like Firefox: exclusive locking with uncheckpointed changes still in the WAL.
        let firefoxConnection = try SQLiteDatabase(firefox.database)
        try firefoxConnection.execute("""
            PRAGMA locking_mode = EXCLUSIVE;
            INSERT INTO moz_places (id, url, title) VALUES (999, 'https://during.example/', NULL);
            INSERT INTO moz_bookmarks (type, fk, parent, position, title) VALUES (1, 999, 3, 999, 'During');
            """)
        #expect(throws: SQLiteError.self) {
            try SQLiteDatabase(firefox.database).query("SELECT 1 FROM moz_bookmarks") { _ in }
        }

        let titles = try FirefoxBookmarks.read(profile: firefox.profile).map(\.title)
        #expect(Set(titles) == ["Before", "During"])
        withExtendedLifetime(firefoxConnection) {}
    }

    @Test func findsProfilesDefaultsFirst() throws {
        let other = firefox.directory.appendingPathComponent("Profiles/zzz.other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try Data().write(to: other.appendingPathComponent("places.sqlite"))
        let empty = firefox.directory.appendingPathComponent("Profiles/empty.default")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)

        try firefox.write("profiles.ini", """
            [Profile0]
            Name=other
            IsRelative=1
            Path=Profiles/zzz.other

            [Profile1]
            Name=empty
            IsRelative=1
            Path=Profiles/empty.default
            Default=1
            """)
        try firefox.write("installs.ini", """
            [2656FF1E876E9973]
            Default=Profiles/abc.default-release
            Locked=1
            """)

        let names = FirefoxBookmarks.profiles(in: firefox.directory).map(\.lastPathComponent)
        #expect(names == ["abc.default-release", "zzz.other"])
    }

    @Test func noFirefoxMeansNoProfiles() {
        #expect(FirefoxBookmarks.profiles(in: URL(fileURLWithPath: "/nonexistent-\(UUID())")).isEmpty)
    }
}

@Suite struct FirefoxBookmarkProviderTests {
    let firefox: FakeFirefox
    let browser = URL(fileURLWithPath: "/Applications/Firefox.app")

    init() throws {
        firefox = try FakeFirefox()
        try firefox.bookmark("https://github.com/apple/swift", title: "Swift on GitHub", tags: [11])
        try firefox.bookmark("https://news.ycombinator.com/", title: "Hacker News", keyword: "hn")
        try firefox.bookmark("https://www.example.com/dashboards/", title: "Grafana", folder: 10)
    }

    private func provider() -> FirefoxBookmarkProvider {
        let provider = FirefoxBookmarkProvider(directory: firefox.directory, browser: browser)
        provider.reloadIfChanged()
        return provider
    }

    private func search(_ text: String, in provider: FirefoxBookmarkProvider) async -> [SearchResult] {
        await SearchEngine(providers: [provider]).search(text)
    }

    @Test func matchesTitlesWithHighlights() async throws {
        let provider = provider()
        let result = try #require(await search("hack", in: provider).first)
        #expect(result.title == "Hacker News")
        #expect(result.titleMatches == [0, 1, 2, 3])
        #expect(result.subtitle == "news.ycombinator.com  ·  Bookmarks Toolbar")
        #expect(result.action == .openWith(URL(string: "https://news.ycombinator.com/")!, application: browser))
        #expect(result.alternateAction == .copyToClipboard("https://news.ycombinator.com/"))
    }

    @Test func matchesURLTagsKeywordsAndFolderWithoutHighlights() async throws {
        let provider = provider()
        for (query, title) in [("ycombinator", "Hacker News"), ("work", "Swift on GitHub"),
                               ("hn", "Hacker News"), ("dev", "Grafana"), ("dashboards", "Grafana")] {
            let result = try #require(await search(query, in: provider).first, "\(query)")
            #expect(result.title == title, "\(query)")
            #expect(result.titleMatches.isEmpty, "\(query)")
        }
    }

    @Test func titleMatchesOutrankAnExactFolderName() async throws {
        try firefox.bookmark("https://portal.example/", title: "Dev Portal", folder: 10)
        let results = await search("dev", in: provider())
        #expect(results.map(\.title) == ["Dev Portal", "Grafana"])
        #expect(results.first?.titleMatches == [0, 1, 2])
    }

    @Test func exactKeywordWinsOutright() async throws {
        try firefox.bookmark("https://hn.example/", title: "HN Clone")
        #expect(await search("hn", in: provider()).first?.title == "Hacker News")
    }

    @Test func titleMatchesOutrankOtherFields() async throws {
        try firefox.bookmark("https://swift.example/", title: "Unrelated", folder: 2, keyword: "swiftly")
        let titles = await search("swift", in: provider()).map(\.title)
        #expect(titles == ["Swift on GitHub", "Unrelated"])
    }

    @Test func ranksBelowAnEquallyGoodApplication() async throws {
        let fake = try FakeApplications()
        try fake.app("Grafana.app")
        let apps = ApplicationProvider(scanner: ApplicationScanner(locations: [.init(fake.root, depth: 1)]))
        apps.reload()

        let results = await SearchEngine(providers: [provider(), apps]).search("grafana")
        #expect(results.map { $0.id.hasPrefix("app:") } == [true, false])
    }

    @Test func reloadsOnlyWhenTheDatabaseChanges() async throws {
        let provider = provider()
        #expect(provider.bookmarks.count == 3)
        #expect(provider.reloadIfChanged() == false)

        try firefox.bookmark("https://new.example/", title: "Brand New")
        #expect(provider.reloadIfChanged() == true)
        #expect(await search("brand", in: provider).first?.title == "Brand New")
    }

    @Test func reportsUnreadableDatabases() throws {
        try "not a database".write(to: firefox.database, atomically: true, encoding: .utf8)
        try? FileManager.default.removeItem(at: firefox.profile.appendingPathComponent("places.sqlite-wal"))
        let provider = FirefoxBookmarkProvider(directory: firefox.directory)
        #expect(provider.reloadIfChanged() == false)
        #expect(provider.problem?.hasPrefix("Firefox bookmarks (abc.default-release):") == true)
    }

    @Test func keywordGatesBookmarkSearches() async throws {
        let bookmarks = FirefoxBookmarkProvider(directory: firefox.directory, browser: browser, keyword: "b")
        bookmarks.reloadIfChanged()
        let fake = try FakeApplications()
        try fake.app("Hacker Tools.app")
        let apps = ApplicationProvider(scanner: ApplicationScanner(locations: [.init(fake.root, depth: 1)]))
        apps.reload()
        let engine = SearchEngine(providers: [apps, bookmarks])

        #expect(await engine.search("hacker").map(\.title) == ["Hacker Tools"])
        #expect(await engine.search("b hacker").map(\.title) == ["Hacker News"])
        #expect(await engine.search("B  hack").map(\.title) == ["Hacker News"])
        // Just the keyword: a hint, not a list of everything.
        let hint = try #require(await engine.search("b ").first)
        #expect(hint.title == "Search Firefox Bookmarks")
        #expect(hint.subtitle.hasPrefix("3 bookmarks"))
        // Without the space, "b" is an ordinary query.
        #expect(await engine.search("b").allSatisfy { $0.title != "Search Firefox Bookmarks" })
    }

    @Test func suggestsTheKeywordForRelatedQueries() async throws {
        let bookmarks = FirefoxBookmarkProvider(directory: firefox.directory, keyword: "b")
        bookmarks.reloadIfChanged()
        let engine = SearchEngine(providers: [bookmarks])
        for text in ["firefox", "bookm", "search fire"] {
            let results = await engine.search(text)
            #expect(results.map(\.title) == ["Search Firefox Bookmarks"], "\(text)")
            #expect(results.first?.action == .autocomplete("b "), "\(text)")
        }
        #expect(await engine.search("fi").isEmpty)
        #expect(await engine.search("hacker").isEmpty)
    }

    @Test func displayURLDropsSchemeAndWWW() {
        #expect(FirefoxBookmarkProvider.displayURL(URL(string: "https://www.example.com/a/")!) == "example.com/a")
        #expect(FirefoxBookmarkProvider.displayURL(URL(string: "http://example.com")!) == "example.com")
        #expect(FirefoxBookmarkProvider.displayURL(URL(string: "file:///tmp/x")!) == "file:///tmp/x")
    }
}
