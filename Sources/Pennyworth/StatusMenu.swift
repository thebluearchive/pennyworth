import AppKit
import PennyworthCore

/// The menu bar item: open the launcher, switch themes, reach the config.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private weak var app: AppDelegate?

    init(app: AppDelegate) {
        self.app = app
        super.init()
        item.button?.image = NSImage(
            systemSymbolName: "magnifyingglass", accessibilityDescription: "Pennyworth")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let app else { return }

        let hotkey = KeyCombination(app.config.hotkey).map { " (\($0))" } ?? ""
        menu.addItem(ActionMenuItem("Open Pennyworth\(hotkey)") { app.showLauncher() })
        menu.addItem(.separator())

        let themes = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        themes.submenu = themeMenu(app)
        menu.addItem(themes)
        menu.addItem(.separator())

        menu.addItem(ActionMenuItem("Open Config Folder") { app.openConfigFolder() })
        menu.addItem(ActionMenuItem("Reload Config") { app.reloadSettings() })

        let problems = app.problems
        if !problems.isEmpty {
            menu.addItem(.separator())
            for problem in problems {
                let item = NSMenuItem(title: "⚠︎ \(problem)", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(ActionMenuItem("Quit Pennyworth", key: "q") { NSApp.terminate(nil) })
    }

    private func themeMenu(_ app: AppDelegate) -> NSMenu {
        let menu = NSMenu()
        let current = app.currentTheme.id
        let groups = [app.themes.themes.filter(\.isBuiltIn), app.themes.themes.filter { !$0.isBuiltIn }]
        for group in groups where !group.isEmpty {
            if menu.numberOfItems > 0 { menu.addItem(.separator()) }
            for theme in group {
                let item = ActionMenuItem(theme.name) { app.selectTheme(theme.id) }
                item.state = theme.id == current ? .on : .off
                menu.addItem(item)
            }
        }
        return menu
    }
}

/// A menu item that runs a closure.
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func run() {
        handler()
    }
}
