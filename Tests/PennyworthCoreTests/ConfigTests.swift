import Foundation
import Testing
@testable import PennyworthCore

@Suite struct ConfigStoreTests {
    let store: ConfigStore

    init() {
        store = ConfigStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("pennyworth-config-\(UUID().uuidString)/config.json"))
    }

    @Test func missingFileGivesDefaults() throws {
        #expect(try store.load() == Config())
        #expect(Config().theme == "tokyo-night")
    }

    @Test func partialFileKeepsDefaultsForMissingKeys() throws {
        try FileManager.default.createDirectory(
            at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{ "theme": "nord" }"#.write(to: store.url, atomically: true, encoding: .utf8)
        let config = try store.load()
        #expect(config.theme == "nord")
        #expect(config.hotkey == Config().hotkey)
    }

    @Test func invalidFileThrowsAReadableError() throws {
        try FileManager.default.createDirectory(
            at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{ "maxVisibleResults": "lots" }"#.write(to: store.url, atomically: true, encoding: .utf8)
        #expect {
            try store.load()
        } throws: { error in
            String(describing: error).hasPrefix("config.json: maxVisibleResults:")
        }
    }

    @Test func savePreservesUnknownKeys() throws {
        try FileManager.default.createDirectory(
            at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{ "theme": "nord", "futureSetting": [1, 2] }"#.write(to: store.url, atomically: true, encoding: .utf8)

        var config = try store.load()
        config.theme = "dracula"
        try store.save(config)

        #expect(try store.load().theme == "dracula")
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: store.url)) as? [String: Any]
        #expect(raw?["futureSetting"] as? [Int] == [1, 2])
    }
}

@Suite struct KeyCombinationTests {
    @Test func parsesModifiersAndKey() throws {
        let combo = try #require(KeyCombination("option+space"))
        #expect(combo.keyCode == 0x31)
        #expect(combo.modifiers == [.option])
        #expect(combo.description == "⌥Space")
    }

    @Test func acceptsAliasesInAnyCaseAndOrder() throws {
        let combo = try #require(KeyCombination("Shift + CMD + k"))
        #expect(combo.keyCode == 0x28)
        #expect(combo.modifiers == [.command, .shift])
        #expect(combo.description == "⇧⌘K")
        #expect(KeyCombination("alt+ctrl+f12")?.description == "⌃⌥F12")
        #expect(KeyCombination("cmd+/")?.keyCode == 0x2C)
    }

    @Test func rejectsInvalidSpecs() {
        for bad in ["", "option+", "hyper+space", "option+spacebar", "cmd+a+b"] {
            #expect(KeyCombination(bad) == nil, "\(bad)")
        }
    }
}
