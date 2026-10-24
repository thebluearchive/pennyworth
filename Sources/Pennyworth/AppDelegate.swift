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
    private let configStore = ConfigStore()

    private(set) var config = Config()
    private(set) var themes = ThemeLibrary()
    /// Set while config.json is unreadable; saving is skipped so the file isn't clobbered.
    private var configError: ConfigError?
    private var hotKeyError: String?

    private var hotKey: HotKey?
    private var applications = ApplicationProvider()
    private var launcher: LauncherController!
    private var statusMenu: StatusMenu!

    init(initialQuery: String?, themeOverride: String? = nil, snapshot: URL? = nil) {
        self.initialQuery = initialQuery
        self.themeOverride = themeOverride
        self.snapshot = snapshot
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadSettings()
        let model = LauncherModel(
            engine: SearchEngine(providers: []), theme: currentTheme,
            maxVisibleResults: config.maxVisibleResults)
        launcher = LauncherController(model: model)
        // Cheap enough to do on every open, and keeps newly installed apps findable.
        launcher.onShow = { [weak self] in self?.reindexApplications() }
        statusMenu = StatusMenu(app: self)

        rebuildProviders()
        registerHotKey()
        if let themeOverride, let theme = themes.theme(withID: themeOverride) {
            launcher.model.theme = theme
            launcher.applyTheme()
        }
        if let initialQuery {
            launcher.show()
            launcher.model.setQuery(initialQuery)
        }
        if let snapshot {
            Task { @MainActor in
                // Give the app scan and SwiftUI a moment to settle.
                try? await Task.sleep(for: .seconds(1.5))
                do {
                    try launcher.writeSnapshot(to: snapshot)
                } catch {
                    FileHandle.standardError.write(Data("Snapshot failed: \(error)\n".utf8))
                }
                NSApp.terminate(nil)
            }
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
        var problems = [configError?.description, hotKeyError].compactMap { $0 }
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
        guard let theme = themes.theme(withID: id) else { return }
        config.theme = id
        launcher.model.theme = theme
        launcher.applyTheme()
        saveConfig()
    }

    func reloadSettings() {
        loadSettings()
        launcher.model.theme = currentTheme
        launcher.model.maxVisibleResults = config.maxVisibleResults
        launcher.applyTheme()
        rebuildProviders()
        registerHotKey()
    }

    func openConfigFolder() {
        do {
            try FileManager.default.createDirectory(at: Paths.themesDirectory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: configStore.url.path) {
                try configStore.save(config)
            }
        } catch {
            log.error("Couldn't create config folder: \(error.localizedDescription)")
        }
        NSWorkspace.shared.open(Paths.configDirectory)
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

    private func rebuildProviders() {
        applications = ApplicationProvider(scanner: ApplicationScanner(config: config))
        launcher.model.engine = SearchEngine(providers: [applications])
        reindexApplications()
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
                        "hotkey" in config.json (e.g. "cmd+shift+space") and choose Reload Config \
                        from the menu bar icon.
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
