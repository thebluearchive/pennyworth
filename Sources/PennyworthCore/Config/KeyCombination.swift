import Foundation

/// A global shortcut such as `"option+space"` or `"cmd+shift+k"`.
public struct KeyCombination: Sendable, Hashable, CustomStringConvertible {
    public struct Modifiers: OptionSet, Sendable, Hashable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    /// macOS virtual key code (`kVK_*`, ANSI layout).
    public let keyCode: UInt32
    public let modifiers: Modifiers
    let keyLabel: String

    /// Parses `+`-separated modifiers followed by one key. Case-insensitive.
    public init?(_ spec: String) {
        let parts = spec.lowercased().split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let keyName = parts.last, !keyName.isEmpty,
              let key = Self.keys[keyName] else { return nil }

        var modifiers: Modifiers = []
        for name in parts.dropLast() {
            guard let modifier = Self.modifierNames[name] else { return nil }
            modifiers.insert(modifier)
        }
        self.keyCode = key.code
        self.modifiers = modifiers
        self.keyLabel = key.label
    }

    /// Mac-style label, e.g. `⌥Space`.
    public var description: String {
        let symbols: [(Modifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { modifiers.contains($0.0) }.map(\.1).joined() + keyLabel
    }

    private static let modifierNames: [String: Modifiers] = [
        "ctrl": .control, "control": .control, "⌃": .control,
        "opt": .option, "option": .option, "alt": .option, "⌥": .option,
        "shift": .shift, "⇧": .shift,
        "cmd": .command, "command": .command, "⌘": .command,
    ]

    private static let keys: [String: (code: UInt32, label: String)] = {
        var keys: [String: (UInt32, String)] = [:]
        let letters: [(Character, UInt32)] = [
            ("a", 0x00), ("s", 0x01), ("d", 0x02), ("f", 0x03), ("h", 0x04), ("g", 0x05),
            ("z", 0x06), ("x", 0x07), ("c", 0x08), ("v", 0x09), ("b", 0x0B), ("q", 0x0C),
            ("w", 0x0D), ("e", 0x0E), ("r", 0x0F), ("y", 0x10), ("t", 0x11), ("o", 0x1F),
            ("u", 0x20), ("i", 0x22), ("p", 0x23), ("l", 0x25), ("j", 0x26), ("k", 0x28),
            ("n", 0x2D), ("m", 0x2E),
        ]
        for (letter, code) in letters {
            keys[String(letter)] = (code, letter.uppercased())
        }
        let digits: [UInt32] = [0x1D, 0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19]
        for (digit, code) in digits.enumerated() {
            keys[String(digit)] = (code, String(digit))
        }
        let functionKeys: [UInt32] = [
            0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D,
            0x67, 0x6F, 0x69, 0x6B, 0x71, 0x6A, 0x40, 0x4F, 0x50, 0x5A,
        ]
        for (index, code) in functionKeys.enumerated() {
            keys["f\(index + 1)"] = (code, "F\(index + 1)")
        }
        let named: [([String], UInt32, String)] = [
            (["space"], 0x31, "Space"),
            (["return", "enter"], 0x24, "↩"),
            (["tab"], 0x30, "⇥"),
            (["escape", "esc"], 0x35, "⎋"),
            (["`", "grave", "backtick"], 0x32, "`"),
            (["-", "minus"], 0x1B, "-"),
            (["=", "equal"], 0x18, "="),
            (["[", "leftbracket"], 0x21, "["),
            (["]", "rightbracket"], 0x1E, "]"),
            ([";", "semicolon"], 0x29, ";"),
            (["'", "quote"], 0x27, "'"),
            ([",", "comma"], 0x2B, ","),
            ([".", "period"], 0x2F, "."),
            (["/", "slash"], 0x2C, "/"),
            (["\\", "backslash"], 0x2A, "\\"),
        ]
        for (names, code, label) in named {
            for name in names { keys[name] = (code, label) }
        }
        return keys
    }()
}
