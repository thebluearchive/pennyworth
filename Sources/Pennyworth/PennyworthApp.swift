import AppKit
import PennyworthCore

@main
enum PennyworthApp {
    @MainActor
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())

        // `Pennyworth --search <query>` prints ranked results; handy for tuning.
        if arguments.first == "--search" {
            printSearchResults(for: arguments.dropFirst().joined(separator: " "))
            return
        }

        // `--show [query]` opens the launcher immediately, optionally pre-filled.
        var initialQuery: String?
        if let index = arguments.firstIndex(of: "--show") {
            initialQuery = arguments.dropFirst(index + 1).first { !$0.hasPrefix("--") } ?? ""
        }

        // `--snapshot <file.png>` renders the launcher to an image and quits (needs no
        // screen recording permission). Combine with `--show <query>` and `--theme <id>`.
        let snapshot = value(after: "--snapshot", in: arguments).map { URL(fileURLWithPath: $0) }

        let app = NSApplication.shared
        let delegate = AppDelegate(
            initialQuery: initialQuery, themeOverride: value(after: "--theme", in: arguments),
            snapshot: snapshot)
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    private static func printSearchResults(for query: String) {
        let config = (try? ConfigStore().load()) ?? Config()
        let applications = ApplicationProvider(scanner: ApplicationScanner(config: config))
        let start = Date()
        applications.reload()
        print("Indexed \(applications.applications.count) apps in \(Int(Date().timeIntervalSince(start) * 1000)) ms")

        var providers: [any SearchProvider] = [applications]
        if config.firefoxBookmarks {
            let bookmarks = FirefoxBookmarkProvider()
            bookmarks.reloadIfChanged()
            print("Read \(bookmarks.bookmarks.count) Firefox bookmarks" + (bookmarks.problem.map { " (\($0))" } ?? ""))
            providers.append(bookmarks)
        }
        let engine = SearchEngine(providers: providers)
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            for result in await engine.search(query, limit: 15) {
                print(String(format: "%7.3f  ", result.score) + "\(result.title)  —  \(result.subtitle)")
            }
            done.signal()
        }
        done.wait()
    }
}

extension ApplicationScanner {
    init(config: Config) {
        self.init(locations: Self.defaultLocations
            + config.applicationFolders.map { Location(path: $0, depth: 2) })
    }
}
