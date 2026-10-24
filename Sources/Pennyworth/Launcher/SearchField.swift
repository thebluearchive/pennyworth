import AppKit
import PennyworthCore
import SwiftUI

/// An AppKit text field, for control over focus, caret and selection colors.
/// Navigation keys are intercepted earlier by `LauncherController`.
struct SearchField: NSViewRepresentable {
    var text: String
    var placeholder: String
    var theme: Theme
    var focusRequest: Int
    var onChange: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange, theme: theme)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 24, weight: .regular)
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        let coordinator = context.coordinator
        coordinator.onChange = onChange
        coordinator.theme = theme

        if field.stringValue != text {
            field.stringValue = text
        }
        field.textColor = theme.colors.text.nsColor
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .foregroundColor: theme.colors.placeholder.nsColor,
            .font: field.font ?? .systemFont(ofSize: 24),
        ])
        coordinator.styleEditor(of: field)

        if coordinator.focusRequest != focusRequest {
            coordinator.focusRequest = focusRequest
            // The field may not be in a window yet on first layout.
            Task { @MainActor in
                field.window?.makeFirstResponder(field)
                coordinator.styleEditor(of: field)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var onChange: (String) -> Void
        var theme: Theme
        var focusRequest = -1

        init(onChange: @escaping (String) -> Void, theme: Theme) {
            self.onChange = onChange
            self.theme = theme
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            onChange(field.stringValue)
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            styleEditor(of: field)
        }

        /// The caret and selection belong to the window's shared field editor.
        func styleEditor(of field: NSTextField) {
            guard let editor = field.currentEditor() as? NSTextView else { return }
            editor.insertionPointColor = theme.colors.accent.nsColor
            editor.selectedTextAttributes = [
                .backgroundColor: theme.colors.selectionBackground.nsColor,
                .foregroundColor: theme.colors.selectionText.nsColor,
            ]
        }
    }
}
