import Foundation
import Testing
@testable import PennyworthCore

/// Builds a throwaway folder tree of fake `.app` bundles.
final class FakeApplications {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pennyworth-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    @discardableResult
    func app(_ relativePath: String, bundleName: String? = nil, bundleID: String? = nil) throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var info: [String: Any] = [:]
        if let bundleName { info["CFBundleName"] = bundleName }
        if let bundleID { info["CFBundleIdentifier"] = bundleID }
        (info as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"), atomically: true)
        return url
    }
}

@Suite struct ApplicationScannerTests {
    @Test func findsAppsUpToTheConfiguredDepth() throws {
        let fake = try FakeApplications()
        try fake.app("Top.app")
        try fake.app("Vendor/Nested.app")
        try fake.app("Vendor/Deeper/TooDeep.app")
        try fake.app("Top.app/Contents/Helpers/Inner.app")

        let scanner = ApplicationScanner(locations: [.init(fake.root, depth: 2)])
        let names = Set(scanner.scan().map(\.name))
        #expect(names == ["Top", "Nested"])
    }

    @Test func readsBundleMetadata() throws {
        let fake = try FakeApplications()
        try fake.app("Code.app", bundleName: "Visual Studio Code", bundleID: "com.microsoft.VSCode")

        let app = try #require(ApplicationScanner(locations: [.init(fake.root, depth: 1)]).scan().first)
        #expect(app.name == "Code")
        #expect(app.bundleIdentifier == "com.microsoft.VSCode")
        #expect(app.alternateNames == ["Visual Studio Code"])
    }

    @Test func followsSymlinksAndDeduplicates() throws {
        let fake = try FakeApplications()
        let real = try fake.app("Real/Browser.app")
        try FileManager.default.createDirectory(
            at: fake.root.appendingPathComponent("Links"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: fake.root.appendingPathComponent("Links/Browser.app"), withDestinationURL: real)

        let scanner = ApplicationScanner(locations: [
            .init(fake.root.appendingPathComponent("Links"), depth: 1),
            .init(fake.root.appendingPathComponent("Real"), depth: 1),
        ])
        let apps = scanner.scan()
        #expect(apps.count == 1)
        #expect(apps.first?.url.path.hasSuffix("Links/Browser.app") == true)
    }

    @Test func acceptsABundleAsALocation() throws {
        let fake = try FakeApplications()
        let finder = try fake.app("Finder.app")
        let apps = ApplicationScanner(locations: [.init(finder, depth: 0)]).scan()
        #expect(apps.map(\.name) == ["Finder"])
    }

    @Test func toleratesMissingFolders() {
        let scanner = ApplicationScanner(locations: [.init(path: "/nonexistent-\(UUID())", depth: 2)])
        #expect(scanner.scan().isEmpty)
    }
}

@Suite struct ApplicationProviderTests {
    let fake: FakeApplications

    init() throws {
        fake = try FakeApplications()
    }

    private func provider(_ apps: [(String, String?)]) throws -> ApplicationProvider {
        for (path, bundleName) in apps { try fake.app(path, bundleName: bundleName) }
        let provider = ApplicationProvider(scanner: ApplicationScanner(locations: [.init(fake.root, depth: 1)]))
        provider.reload()
        return provider
    }

    @Test func ranksBestMatchFirst() async throws {
        let provider = try provider([
            ("Terminal.app", nil), ("The Remote Manager.app", nil), ("Safari.app", nil),
        ])
        let titles = await SearchEngine(providers: [provider]).search("term").map(\.title)
        #expect(titles == ["Terminal", "The Remote Manager"])
    }

    @Test func matchesAlternateNamesWithoutHighlighting() async throws {
        let provider = try provider([("Code.app", "Visual Studio Code")])
        let result = try #require(await provider.search(SearchQuery("visual")).first)
        #expect(result.title == "Code")
        #expect(result.titleMatches.isEmpty)
    }

    @Test func producesOpenAndRevealActions() async throws {
        let provider = try provider([("Notes.app", nil)])
        let result = try #require(await provider.search(SearchQuery("notes")).first)
        let url = try #require(provider.applications.first?.url)
        #expect(result.id == "app:\(url.path)")
        #expect(result.action == .open(url))
        #expect(result.alternateAction == .revealInFinder(url))
        #expect(result.titleMatches == [0, 1, 2, 3, 4])
    }

    @Test func emptyQueryReturnsNothing() async throws {
        let provider = try provider([("Notes.app", nil)])
        #expect(await SearchEngine(providers: [provider]).search("   ").isEmpty)
    }
}
