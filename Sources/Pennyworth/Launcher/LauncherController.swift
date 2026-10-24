import AppKit
import Carbon.HIToolbox
import OSLog
import PennyworthCore
import SwiftUI

private let log = Logger(subsystem: "dev.pennyworth", category: "launcher")

/// Owns the launcher panel: showing, sizing, keyboard handling and running actions.
@MainActor
final class LauncherController: NSObject, NSWindowDelegate {
    let model: LauncherModel
    var onCommand: ((LauncherCommand) -> Void)?
    /// For scripted debug runs: show the panel off-screen without taking keyboard focus,
    /// so it neither interrupts nor picks up the user's typing.
    var isHeadless = false
    var onShow: (() -> Void)?
    /// Resolves theme ids for live preview while browsing theme results.
    var themeLookup: ((String) -> Theme?)?

    private let panel = LauncherPanel()
    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    /// Trackpad scrolling not yet amounting to a whole row, in points.
    private var pendingScroll: CGFloat = 0

    init(model: LauncherModel) {
        self.model = model
        super.init()

        let content = NSHostingView(rootView: LauncherView(model: model) { [weak self] index in
            self?.activate(index: index, alternate: false)
        })
        // Size is driven by `updateSize()`, not by SwiftUI.
        content.sizingOptions = []
        panel.contentView = content
        panel.delegate = self
        model.onChange = { [weak self] in
            self?.updateSize()
            self?.updatePreview()
        }
        applyTheme()
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        onShow?()
        placeOnActiveScreen()
        if isHeadless {
            panel.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
            panel.orderFrontRegardless()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
        model.requestFocus()
        installKeyMonitor()
        installScrollMonitor()
    }

    func hide() {
        guard isVisible else { return }
        panel.orderOut(nil)
        removeKeyMonitor()
        model.reset()
    }

    func applyTheme() {
        panel.appearance = NSAppearance(named: model.activeTheme.appearance == .dark ? .darkAqua : .aqua)
        invalidateShadowSoon()
    }

    /// Previews the selected theme result; reverts when anything else is selected.
    private func updatePreview() {
        var preview: Theme?
        if case .command(.setTheme(let id)) = model.selectedResult?.action {
            preview = themeLookup?(id)
        }
        guard preview != model.previewTheme else { return }
        model.previewTheme = preview
        applyTheme()
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    /// Types into the search field via the field editor, like the keyboard does. `↓ ↑ ⇥ ↩`
    /// are sent as key events through the event queue. For debugging.
    func simulateTyping(_ text: String, interval: Duration) async {
        let keys: [Character: Int] = ["↓": kVK_DownArrow, "↑": kVK_UpArrow, "⇥": kVK_Tab, "↩": kVK_Return]
        for character in text {
            if let keyCode = keys[character],
               let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                isARepeat: false, keyCode: UInt16(keyCode)) {
                NSApp.postEvent(event, atStart: false)
            } else {
                (panel.firstResponder as? NSTextView)?.insertText(
                    String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
            }
            try? await Task.sleep(for: interval)
        }
    }

    /// Renders the panel's content to a PNG, for previews and debugging.
    func writeSnapshot(to url: URL) throws {
        guard let view = panel.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: url)
    }

    // MARK: Layout

    private var height: CGFloat {
        LauncherLayout.height(resultCount: model.results.count, maxVisible: model.maxVisibleResults)
    }

    private func placeOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let top = visible.maxY - visible.height * 0.2
        panel.setFrame(NSRect(
            x: visible.midX - LauncherLayout.width / 2, y: top - height,
            width: LauncherLayout.width, height: height), display: true)
        invalidateShadowSoon()
    }

    private func updateSize() {
        var frame = panel.frame
        guard frame.height != height else { return }
        let top = frame.maxY
        frame.size.height = height
        frame.origin.y = top - height
        panel.setFrame(frame, display: true)
        invalidateShadowSoon()
    }

    /// The shadow follows the content's alpha, so recompute it once SwiftUI has redrawn.
    private func invalidateShadowSoon() {
        Task { @MainActor [panel] in panel.invalidateShadow() }
    }

    // MARK: Keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handleKeyDown(event) ?? false }
            return handled ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
    }

    /// The list isn't a scroll view, so turn wheel and trackpad scrolling into whole rows.
    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        pendingScroll = 0
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handleScroll(event) ?? false }
            return handled ? nil : event
        }
    }

    private func handleScroll(_ event: NSEvent) -> Bool {
        guard event.window === panel else { return false }
        if event.phase == .began { pendingScroll = 0 }
        // Positive deltas reveal earlier rows, like a scroll view.
        pendingScroll -= event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaY : event.scrollingDeltaY * LauncherLayout.rowHeight
        let rows = Int(pendingScroll / LauncherLayout.rowHeight)
        if rows != 0 {
            pendingScroll -= CGFloat(rows) * LauncherLayout.rowHeight
            model.scroll(byRows: rows)
        }
        return true
    }

    /// Returns true if the event was consumed.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard event.window === panel else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        switch Int(event.keyCode) {
        case kVK_DownArrow:
            model.moveSelection(by: 1)
            return true
        case kVK_UpArrow:
            model.moveSelection(by: -1)
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            activate(index: model.selection, alternate: flags.contains(.command))
            return true
        case kVK_Escape:
            hide()
            return true
        case kVK_Tab:
            if let completion = model.selectedResult?.autocomplete {
                model.setQuery(completion)
            }
            return true
        default:
            break
        }

        if flags == .control {
            switch key {
            case "n", "j": model.moveSelection(by: 1); return true
            case "p", "k": model.moveSelection(by: -1); return true
            default: break
            }
        }

        if flags.contains(.command) {
            if let digit = Int(key), (1...9).contains(digit) {
                activate(index: model.window.first + digit - 1, alternate: false)
                return true
            }
            // No main menu means no Edit menu, so route the standard editing shortcuts by hand.
            let editing: [String: String] = [
                "a": "selectAll:", "c": "copy:", "v": "paste:", "x": "cut:",
                "z": flags.contains(.shift) ? "redo:" : "undo:",
            ]
            if let selector = editing[key] {
                return NSApp.sendAction(Selector(selector), to: nil, from: self)
            }
        }
        return false
    }

    // MARK: Actions

    private func activate(index: Int, alternate: Bool) {
        guard model.results.indices.contains(index) else { return }
        let result = model.results[index]
        perform(alternate ? result.alternateAction ?? result.action : result.action)
    }

    private func perform(_ action: ResultAction) {
        switch action {
        case .open(let url):
            hide()
            if url.pathExtension == "app" {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    if let error { log.error("Failed to open \(url.path): \(error.localizedDescription)") }
                }
            } else {
                NSWorkspace.shared.open(url)
            }
        case .openWith(let url, let application):
            hide()
            NSWorkspace.shared.open([url], withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error { log.error("Failed to open \(url) in \(application.path): \(error.localizedDescription)") }
            }
        case .revealInFinder(let url):
            hide()
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .copyToClipboard(let text):
            hide()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case .autocomplete(let text):
            model.setQuery(text)
        case .command(let command):
            onCommand?(command)
        }
    }
}
