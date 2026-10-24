import AppKit
import OSLog
import PennyworthCore

private let log = Logger(subsystem: "dev.pennyworth", category: "app")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Non-nil to open the launcher at startup with this query.
    private let initialQuery: String?
    private let themeOverride: String?
    private let snapshot: URL?
    private let typing: (text: String, interval: Duration)?
    private let configStore = ConfigStore()

    private(set) var config = Config()
    private(set) var themes = ThemeLibrary()
    /// Set while config.json is unreadable; saving is skipped so the file isn't clobbered.
    private var configError: ConfigError?
    private var hotKeyError: String?

    private var hotKey: HotKey?
    private var applications = ApplicationProvider()
    private var bookmarks: FirefoxBookmarkProvider?
    private let themeProvider = ThemeProvider()
    private var launcher: LauncherController!
    private var statusMenu: StatusMenu!
    private var configWatcher: FileWatcher?
    private var applicationsWatcher: FileWatcher?

    init(
        initialQuery: String?, themeOverride: String? = nil, snapshot: URL? = nil,
        typing: (text: String, interval: Duration)? = nil
    ) {
        self.initialQuery = initialQuery
        self.themeOverride = themeOverride
        self.snapshot = snapshot
        self.typing = typing
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadSettings()
        let model = LauncherModel(
            engine: SearchEngine(providers: []), theme: currentTheme,
            maxVisibleResults: config.maxVisibleResults)
        launcher = LauncherController(model: model)
        launcher.themeLookup = { [weak self] id in self?.themes.theme(withID: id) }
        launcher.onCommand = { [weak self] command in self?.perform(command) }
        // Bookmarks change while Firefox runs; checking is cheap when they haven't.
        launcher.onShow = { [weak self] in self?.reloadBookmarks() }
        statusMenu = StatusMenu(app: self)

        rebuildBookmarks()
        rebuildApplications()
        registerHotKey()
        watchConfig()

        if let themeOverride, let theme = themes.theme(withID: themeOverride) {
            launcher.model.theme = theme
            launcher.applyTheme()
        }
        if let initialQuery {
            launcher.show()
            launcher.model.setQuery(initialQuery)
        }
        if typing != nil || snapshot != nil {
            runDebugScript()
        }
    }

    /// `--type` and `--snapshot`: type into the launcher, then render it and quit.
    private func runDebugScript() {
        Task { @MainActor in
            if let typing {
                if !launcher.isVisible { launcher.show() }
                try? await Task.sleep(for: .milliseconds(300))
                await launcher.simulateTyping(typing.text, interval: typing.interval)
            }
            guard let snapshot else { return }
            // Give the app scan and SwiftUI a moment to settle.
            try? await Task.sleep(for: .seconds(1.5))
            let model = launcher.model
            print("query=\"\(model.query)\" selection=\(model.selection) \(model.selectedResult?.title ?? "-") results=\(model.results.prefix(5).map(\.title))")
            do {
                try launcher.writeSnapshot(to: snapshot)
            } catch {
                FileHandle.standardError.write(Data("Snapshot failed: \(error)\n".utf8))
            }
            NSApp.terminate(nil)
        }
    }

    /// Opening the app again (Finder, `open`, Spotlight) shows the launcher.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        launcher.show()
        return false
    }

    // MARK: State

    var currentTheme: Theme {
        themes.theme(withID: config.theme) ?? themes.theme(withID: Theme.defaultID) ?? .tokyoNight
    }

    /// Everything the user should know is misconfigured, for the status menu.
    var problems: [String] {
        var problems = [configError?.description, hotKeyError, bookmarks?.problem].compactMap { $0 }
        if themes.theme(withID: config.theme) == nil {
            problems.append("Unknown theme \"\(config.theme)\", using \(currentTheme.name)")
        }
        return problems + themes.problems.map { "themes/\($0)" }
    }

    // MARK: Actions

    func showLauncher() {
        launcher.show()
    }

    func selectTheme(_ id: String) {
        guard themes.theme(withID: id) != nil else { return }
        config.theme = id
        applyThemes()
        saveConfig()
    }

    /// Re-reads config.json and the themes folder, applying only what changed.
    /// `userInitiated` also retries a hotkey that another app was holding.
    func reloadSettings(userInitiated: Bool = true) {
        let previous = config
        let previousThemes = themes.themes
        loadSettings()

        if config.theme != previous.theme || themes.themes != previousThemes {
            applyThemes()
        }
        if config.maxVisibleResults != previous.maxVisibleResults {
            launcher.model.maxVisibleResults = config.maxVisibleResults
            launcher.model.refresh()
        }
        if config.firefoxBookmarks != previous.firefoxBookmarks {
            rebuildBookmarks()
            updateEngine()
        }
        if config.applicationFolders != previous.applicationFolders {
            rebuildApplications()
        }
        if config.hotkey != previous.hotkey || (userInitiated && hotKey == nil) {
            registerHotKey()
        }
    }

    func openConfigFolder() {
        if !FileManager.default.fileExists(atPath: configStore.url.path) {
            saveConfig()
        }
        NSWorkspace.shared.open(Paths.configDirectory)
    }

    private func perform(_ command: LauncherCommand) {
        switch command {
        case .setTheme(let id):
            selectTheme(id)
        }
    }

    // MARK: Setup

    private func loadSettings() {
        do {
            config = try configStore.load()
            configError = nil
        } catch {
            config = Config()
            configError = error as? ConfigError
                ?? ConfigError(file: configStore.url, reason: error.localizedDescription)
        }
        themes = ThemeLibrary.load(from: Paths.themesDirectory)
    }

    private func saveConfig() {
        guard configError == nil else { return }
        do {
            try configStore.save(config)
        } catch {
            log.error("Couldn't save config: \(error.localizedDescription)")
        }
    }

    private func applyThemes() {
        themeProvider.update(themes: themes.themes, currentID: currentTheme.id)
        launcher.model.theme = currentTheme
        launcher.applyTheme()
        launcher.model.refresh()
    }

    /// Edits to config.json or theme files apply as soon as they're saved.
    private func watchConfig() {
        try? FileManager.default.createDirectory(at: Paths.themesDirectory, withIntermediateDirectories: true)
        configWatcher = FileWatcher(paths: [Paths.configDirectory.path], latency: 0.3) { [weak self] in
            Task { @MainActor in self?.reloadSettings(userInitiated: false) }
        }
    }

    private func updateEngine() {
        let providers: [(any SearchProvider)?] = [applications, bookmarks, themeProvider]
        launcher.model.engine = SearchEngine(providers: providers.compactMap { $0 })
        launcher.model.refresh()
    }

    private func rebuildBookmarks() {
        guard config.firefoxBookmarks else {
            bookmarks = nil
            return
        }
        let firefox = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.mozilla.firefox")
        bookmarks = FirefoxBookmarkProvider(icon: firefox.map { .file($0) } ?? .symbol("bookmark"), browser: firefox)
        reloadBookmarks()
    }

    private func reloadBookmarks() {
        guard let bookmarks else { return }
        Task.detached(priority: .userInitiated) { [weak self] in
            guard bookmarks.reloadIfChanged() else { return }
            await self?.launcher.model.refresh()
        }
    }

    private func rebuildApplications() {
        let scanner = ApplicationScanner(config: config)
        applications = ApplicationProvider(scanner: scanner)
        themeProvider.update(themes: themes.themes, currentID: currentTheme.id)
        updateEngine()
        reindexApplications()
        applicationsWatcher = FileWatcher(paths: scanner.watchedPaths, latency: 2) { [weak self] in
            Task { @MainActor in self?.reindexApplications() }
        }
    }

    private func reindexApplications() {
        let applications = applications
        Task.detached(priority: .userInitiated) { [weak self] in
            guard applications.reload() else { return }
            await self?.launcher.model.refresh()
        }
    }

    private func registerHotKey() {
        hotKey?.unregister()
        hotKey = nil
        hotKeyError = nil

        guard let combination = KeyCombination(config.hotkey) else {
            hotKeyError = "Invalid hotkey \"\(config.hotkey)\""
            return
        }
        do {
            hotKey = try HotKey(combination) { [weak self] in self?.launcher.toggle() }
        } catch {
            hotKeyError = "\(combination) is used by another app"
            Task { @MainActor in
                self.alert(
                    "\(combination) is already in use",
                    info: """
                        Another app (Alfred or Spotlight?) owns this shortcut. Free it there, or set \
                        "hotkey" in config.json (e.g. "cmd+shift+space"). Changes apply when you save.
                        """)
            }
        }
    }

    private func alert(_ message: String, info: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Config Folder")
        if alert.runModal() == .alertSecondButtonReturn {
            openConfigFolder()
        }
    }
}
