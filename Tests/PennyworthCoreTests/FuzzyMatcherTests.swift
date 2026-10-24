import Testing
@testable import PennyworthCore

@Suite struct FuzzyMatcherTests {
    private func match(_ query: String, _ text: String) -> FuzzyMatch? {
        FuzzyMatcher.match(FuzzyQuery(query), in: MatchCandidate(text))
    }

    @Test func rejectsNonSubsequences() {
        #expect(match("xyz", "Safari") == nil)
        #expect(match("safarix", "Safari") == nil)
        #expect(match("", "Safari") == nil)
    }

    @Test func rejectsScatteredMatches() {
        #expect(match("safari", "DisplayLink Software Uninstaller") == nil)
        #expect(match("note", "Cisco Secure Client - Socket Filter") == nil)
        // A single character only matches at a word start.
        #expect(match("s", "Messages") == nil)
        #expect(match("s", "Screen Sharing") != nil)
        #expect(match("act", "Contacts") != nil)
    }

    @Test func isCaseAndDiacriticInsensitive() {
        #expect(match("SAF", "safari") != nil)
        #expect(match("cafe", "Café Menu") != nil)
        #expect(match("café", "Cafe Menu") != nil)
    }

    @Test func exactMatchOutranksEverything() throws {
        let exact = try #require(match("notes", "Notes"))
        let prefix = try #require(match("notes", "Notes Helper"))
        #expect(exact.score > prefix.score)
    }

    @Test func prefersWordStartsAndConsecutiveRuns() throws {
        let prefix = try #require(match("term", "Terminal"))
        let scattered = try #require(match("term", "The Remote Manager"))
        #expect(prefix.score > scattered.score)
    }

    @Test func matchesAcronyms() throws {
        let acronym = try #require(match("vsc", "Visual Studio Code"))
        #expect(acronym.positions == [0, 7, 14])
        let partial = try #require(match("vsc", "VS Code"))
        #expect(partial.positions == [0, 1, 3])
        #expect(match("vsc", "Devices Console") == nil)
    }

    @Test func prefersShorterCandidates() throws {
        let short = try #require(match("mail", "Mail App"))
        let long = try #require(match("mail", "Mail App Extension Manager"))
        #expect(short.score > long.score)
    }

    @Test func reportsMatchedPositions() throws {
        let result = try #require(match("gc", "Google Chrome"))
        #expect(result.positions == [0, 7])
        let consecutive = try #require(match("chro", "Google Chrome"))
        #expect(consecutive.positions == [7, 8, 9, 10])
    }

    @Test func camelCaseBoundariesCount() throws {
        let camel = try #require(match("ij", "IntelliJ IDEA"))
        let plain = try #require(match("ij", "Injector"))
        #expect(camel.positions == [0, 7])
        #expect(camel.score > plain.score)
    }
}
