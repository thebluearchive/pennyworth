import Carbon.HIToolbox
import PennyworthCore

/// A system-wide keyboard shortcut, registered through Carbon so it needs no
/// Accessibility permission.
@MainActor
final class HotKey {
    struct UnavailableError: Error {
        let status: OSStatus
    }

    private struct WeakHotKey {
        weak var hotKey: HotKey?
    }

    private static var registered: [UInt32: WeakHotKey] = [:]
    private static var nextID: UInt32 = 1
    private static var eventHandler: EventHandlerRef?

    private let id: UInt32
    private var reference: EventHotKeyRef?
    private let action: () -> Void

    /// Throws if another app already owns the combination.
    init(_ combination: KeyCombination, action: @escaping () -> Void) throws(UnavailableError) {
        Self.installEventHandler()
        id = Self.nextID
        Self.nextID += 1
        self.action = action

        let hotKeyID = EventHotKeyID(signature: OSType(0x5057_5448) /* PWTH */, id: id)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combination.keyCode, Self.carbonModifiers(combination.modifiers), hotKeyID,
            GetEventDispatcherTarget(), OptionBits(kEventHotKeyExclusive), &reference)
        guard status == noErr, let reference else { throw UnavailableError(status: status) }
        self.reference = reference
        Self.registered[id] = WeakHotKey(hotKey: self)
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        Self.registered[id] = nil
    }

    private static func carbonModifiers(_ modifiers: KeyCombination.Modifiers) -> UInt32 {
        var carbon = 0
        if modifiers.contains(.command) { carbon |= cmdKey }
        if modifiers.contains(.option) { carbon |= optionKey }
        if modifiers.contains(.control) { carbon |= controlKey }
        if modifiers.contains(.shift) { carbon |= shiftKey }
        return UInt32(carbon)
    }

    private static func installEventHandler() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            let id = hotKeyID.id
            // Carbon delivers hot key events on the main thread.
            MainActor.assumeIsolated { HotKey.registered[id]?.hotKey?.action() }
            return noErr
        }, 1, &eventType, nil, &eventHandler)
    }
}
