import Foundation
import Testing
@testable import PennyworthCore

@Suite struct SelectionHistoryTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func exactQueryPicksBoostMost() {
        let history = SelectionHistory(file: nil)
        history.record(query: "c", resultID: "chrome", at: now)
        history.record(query: "chr", resultID: "chromium", at: now)

        let boosts = history.boosts(for: "c", at: now)
        #expect(boosts["chrome"] == SelectionHistory.boostPerPick)
        #expect(boosts["chromium"]! < boosts["chrome"]!)
        #expect(boosts["chromium"]! > 0)
        // A longer query isn't boosted by picks for a shorter one.
        #expect(history.boosts(for: "chr", at: now)["chrome"] == nil)
        #expect(history.boosts(for: "x", at: now).isEmpty)
    }

    @Test func repeatedPicksAddLessAndLess() {
        let history = SelectionHistory(file: nil)
        var previous = 0.0
        var previousGain = Double.infinity
        for _ in 1...5 {
            history.record(query: "c", resultID: "chrome", at: now)
            let boost = history.boosts(for: "c", at: now)["chrome"]!
            #expect(boost - previous < previousGain)
            previousGain = boost - previous
            previous = boost
        }
    }

    @Test func normalizesCaseAndSpacing() {
        let history = SelectionHistory(file: nil)
        history.record(query: "  Google   Chr ", resultID: "chrome", at: now)
        #expect(history.boosts(for: "google chr", at: now)["chrome"] == SelectionHistory.boostPerPick)
        history.record(query: "   ", resultID: "nothing", at: now)
        #expect(history.boosts(for: "", at: now).isEmpty)
    }

    @Test func oldPicksFade() {
        let history = SelectionHistory(file: nil)
        history.record(query: "c", resultID: "chrome", at: now)
        let fresh = history.boosts(for: "c", at: now)["chrome"]!
        let later = history.boosts(for: "c", at: now + SelectionHistory.halfLife)["chrome"]!
        #expect(later < fresh)
        #expect(abs(later - SelectionHistory.boostPerPick * log2(1.5)) < 0.0001)
    }

    @Test func persistsAndClears() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("pennyworth-history-\(UUID().uuidString)/knowledge.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let history = SelectionHistory(file: file)
        history.record(query: "c", resultID: "chrome", at: now)
        try history.save()

        let reloaded = SelectionHistory(file: file)
        #expect(reloaded.boosts(for: "c", at: now) == history.boosts(for: "c", at: now))

        reloaded.clear()
        try reloaded.save()
        #expect(SelectionHistory(file: file).isEmpty)
    }

    @Test func ignoresACorruptFile() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("pennyworth-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try "garbage".write(to: file, atomically: true, encoding: .utf8)
        #expect(SelectionHistory(file: file).isEmpty)
    }

    @Test func dropsTheLeastUsedBeyondCapacity() {
        let history = SelectionHistory(file: nil)
        history.record(query: "keep", resultID: "favorite", at: now)
        history.record(query: "keep", resultID: "favorite", at: now)
        history.record(query: "oldest", resultID: "r", at: now - 1)
        for index in 0..<SelectionHistory.capacity {
            history.record(query: "q\(index)", resultID: "r", at: now)
        }
        #expect(history.pairCount == SelectionHistory.capacity)
        #expect(history.boosts(for: "keep", at: now)["favorite"] != nil)
        #expect(history.boosts(for: "oldest", at: now).isEmpty)
    }

    @Test func liftsAPickedResultInTheEngine() async throws {
        let fake = try FakeApplications()
        try fake.app("Calendar.app")
        try fake.app("Google Chrome.app")
        let apps = ApplicationProvider(scanner: ApplicationScanner(locations: [.init(fake.root, depth: 1)]))
        apps.reload()
        let history = SelectionHistory(file: nil)
        let engine = SearchEngine(providers: [apps], history: history)

        let before = await engine.search("c")
        #expect(before.map(\.title) == ["Calendar", "Google Chrome"])

        let chrome = try #require(before.last)
        history.record(query: "c", resultID: chrome.id)
        #expect(await engine.search("c").map(\.title) == ["Google Chrome", "Calendar"])
        // An exact name still wins over a learned pick.
        #expect(await engine.search("calendar").first?.title == "Calendar")
    }
}
