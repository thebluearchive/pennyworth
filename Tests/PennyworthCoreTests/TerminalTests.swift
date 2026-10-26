import Foundation
@testable import PennyworthCore
import Testing

@Suite struct TerminalProviderTests {
    let ghostty = URL(fileURLWithPath: "/Applications/Ghostty.app")

    private func search(_ query: String) async -> [SearchResult] {
        await SearchEngine(providers: [TerminalProvider(terminal: ghostty)]).search(query)
    }

    @Test func runsWhatFollowsTheKeyword() async throws {
        let result = try #require(await search(">  python3 -m http.server").first)
        #expect(result.title == "python3 -m http.server")
        #expect(result.subtitle == "Run in Ghostty")
        #expect(result.action == .runInTerminal("python3 -m http.server", terminal: ghostty))
        #expect(!result.isLearnable)
    }

    @Test func justTheKeywordAsksForACommand() async throws {
        let results = await search("> ")
        #expect(results.map(\.id) == ["terminal:hint"])
    }

    @Test func offersTheKeyword() async throws {
        let hint = try #require(await search(">").first)
        #expect(hint.id == "terminal:hint")
        #expect(hint.action == .autocomplete("> "))
        #expect(await search("shell").map(\.id) == ["terminal:hint"])
        #expect(await search("python3").isEmpty)
    }
}

@Suite struct TerminalScriptTests {
    @Test func quotesForTheShell() {
        #expect(TerminalScript.shellQuoted("ls") == "'ls'")
        #expect(TerminalScript.shellQuoted("echo it's") == #"'echo it'\''s'"#)
    }

    /// Runs a script the way a terminal would, minus the terminal: the command must reach
    /// the shell intact, and the script must clean up after itself.
    @Test func runsTheCommandInTheUsersShellAndDeletesItself() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let command = #"printf '%s|%s' "it's \"quoted\"" "$GREETING" > out.txt"#
        let script = try TerminalScript.write(running: command, in: home)
        let permissions = try FileManager.default.attributesOfItem(atPath: script.path)[.posixPermissions] as? Int
        #expect(permissions == 0o700)

        let process = Process()
        process.executableURL = script
        // An interactive shell reading /dev/null exits right away instead of waiting for input.
        process.environment = ["SHELL": "/bin/zsh", "HOME": home.path, "PATH": "/usr/bin:/bin", "GREETING": "hi"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(10)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { process.terminate() }
        #expect(process.terminationReason == .exit)

        let output = try String(contentsOf: home.appendingPathComponent("out.txt"), encoding: .utf8)
        #expect(output == #"it's "quoted"|hi"#)
        #expect(!FileManager.default.fileExists(atPath: script.path))
    }
}
