import Foundation
import Testing
@testable import PennyworthCore

@Suite struct RGBAColorTests {
    @Test func parsesHexForms() throws {
        let rgb = try #require(RGBAColor(hex: "#1a1b26"))
        #expect(rgb.hex == "#1a1b26")
        #expect(rgb.alpha == 1)

        let rgba = try #require(RGBAColor(hex: "c0caf580"))
        #expect(rgba.hex == "#c0caf580")
        #expect(abs(rgba.alpha - 128.0 / 255) < 0.0001)

        #expect(RGBAColor(hex: "#fff")?.hex == "#ffffff")
    }

    @Test func rejectsMalformedHex() {
        for bad in ["", "#", "#12345", "#gggggg", "#1234567", "red"] {
            #expect(RGBAColor(hex: bad) == nil, "\(bad)")
        }
    }

    @Test func roundTripsThroughJSON() throws {
        let color: RGBAColor = "#7aa2f7"
        let data = try JSONEncoder().encode([color])
        #expect(String(decoding: data, as: UTF8.self) == ##"["#7aa2f7"]"##)
        #expect(try JSONDecoder().decode([RGBAColor].self, from: data) == [color])
    }
}

@Suite struct ThemeLibraryTests {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pennyworth-themes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func write(_ name: String, _ json: String) throws {
        try json.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    @Test func builtInsIncludeTokyoNightAsDefault() throws {
        let library = ThemeLibrary()
        let theme = try #require(library.theme(withID: Theme.defaultID))
        #expect(theme.name == "Tokyo Night")
        #expect(theme.colors.background.hex == "#1a1b26")
        #expect(Set(library.themes.map(\.id)).count == library.themes.count)
    }

    @Test func loadsAThemeThatExtendsABuiltIn() throws {
        try write("purple.json", """
            { "name": "Purple Night", "extends": "tokyo-night",
              "colors": { "accent": "#bb9af7" }, "cornerRadius": 4 }
            """)
        let library = ThemeLibrary.load(from: directory)
        #expect(library.problems.isEmpty)
        let theme = try #require(library.theme(withID: "purple"))
        #expect(theme.name == "Purple Night")
        #expect(theme.colors.accent.hex == "#bb9af7")
        #expect(theme.colors.background == Theme.tokyoNight.colors.background)
        #expect(theme.cornerRadius == 4)
        #expect(theme.appearance == .dark)
        #expect(!theme.isBuiltIn)
    }

    @Test func userThemeCanOverrideTheBuiltInItExtends() throws {
        try write("tokyo-night.json", ##"{ "extends": "tokyo-night", "name": "Mine", "colors": { "border": "#000000" } }"##)
        let library = ThemeLibrary.load(from: directory)
        #expect(library.themes.filter { $0.id == "tokyo-night" }.count == 1)
        #expect(library.theme(withID: "tokyo-night")?.colors.border.hex == "#000000")
    }

    @Test func resolvesChainsInAnyOrder() throws {
        try write("a.json", ##"{ "extends": "b", "colors": { "text": "#111111" } }"##)
        try write("b.json", ##"{ "extends": "nord", "colors": { "accent": "#222222" } }"##)
        let library = ThemeLibrary.load(from: directory)
        let a = try #require(library.theme(withID: "a"))
        #expect(a.colors.text.hex == "#111111")
        #expect(a.colors.accent.hex == "#222222")
        #expect(a.colors.background == Theme.nord.colors.background)
    }

    @Test func standaloneThemeNeedsEveryColor() throws {
        let allColors = Theme.Colors.keys.map { "\"\($0.name)\": \"#101010\"" }.joined(separator: ", ")
        try write("full.json", ##"{ "appearance": "light", "colors": { \##(allColors) } }"##)
        try write("partial.json", ##"{ "appearance": "dark", "colors": { "text": "#ffffff" } }"##)

        let library = ThemeLibrary.load(from: directory)
        #expect(library.theme(withID: "full")?.appearance == .light)
        #expect(library.theme(withID: "partial") == nil)
        #expect(library.problems.count == 1)
        #expect(library.problems.first?.hasPrefix("partial.json: missing background") == true)
    }

    @Test func reportsBadFilesWithoutFailingTheRest() throws {
        try write("syntax.json", "{ nope")
        try write("color.json", #"{ "extends": "nord", "colors": { "text": "blue" } }"#)
        try write("typo.json", ##"{ "extends": "nord", "colors": { "acent": "#ffffff" } }"##)
        try write("orphan.json", #"{ "extends": "missing" }"#)
        try write("loop1.json", #"{ "extends": "loop2" }"#)
        try write("loop2.json", #"{ "extends": "loop1" }"#)
        try write("ok.json", #"{ "extends": "nord" }"#)
        try write("notes.txt", "ignored")

        let library = ThemeLibrary.load(from: directory)
        #expect(library.theme(withID: "ok") != nil)
        #expect(library.themes.count == Theme.builtIn.count + 1)
        let problems = library.problems.joined(separator: "\n")
        #expect(problems.contains("syntax.json"))
        #expect(problems.contains("color.json: colors.text: 'blue' is not a #RRGGBB"))
        #expect(problems.contains("typo.json: unknown colors: acent"))
        #expect(problems.contains("orphan.json: extends unknown theme \"missing\""))
        #expect(problems.contains("loop1.json: circular"))
    }

    @Test func missingDirectoryYieldsBuiltIns() {
        let library = ThemeLibrary.load(from: directory.appendingPathComponent("nope"))
        #expect(library.themes == Theme.builtIn)
        #expect(library.problems.isEmpty)
    }
}
