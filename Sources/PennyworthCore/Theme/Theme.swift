import Foundation

/// An sRGB color, written in JSON as `#RGB`, `#RRGGBB` or `#RRGGBBAA`.
public struct RGBAColor: Sendable, Hashable, Codable, CustomStringConvertible {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init?(hex: String) {
        var digits = Substring(hex.trimmingCharacters(in: .whitespaces))
        if digits.hasPrefix("#") { digits = digits.dropFirst() }
        if digits.count == 3 {
            digits = Substring(digits.flatMap { [$0, $0] })
        }
        guard digits.count == 6 || digits.count == 8,
              let value = UInt32(digits, radix: 16) else { return nil }
        let rgba = digits.count == 6 ? value << 8 | 0xFF : value
        self.init(
            red: Double(rgba >> 24 & 0xFF) / 255,
            green: Double(rgba >> 16 & 0xFF) / 255,
            blue: Double(rgba >> 8 & 0xFF) / 255,
            alpha: Double(rgba & 0xFF) / 255)
    }

    public var hex: String {
        func byte(_ component: Double) -> String {
            String(format: "%02x", Int((min(max(component, 0), 1) * 255).rounded()))
        }
        return "#" + byte(red) + byte(green) + byte(blue) + (alpha < 1 ? byte(alpha) : "")
    }

    public var description: String { hex }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let color = RGBAColor(hex: string) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "'\(string)' is not a #RRGGBB or #RRGGBBAA color")
        }
        self = color
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}

public struct Theme: Sendable, Hashable, Identifiable {
    public enum Appearance: String, Sendable, Hashable, Codable {
        case dark, light
    }

    public struct Colors: Sendable, Hashable {
        public var background: RGBAColor
        public var border: RGBAColor
        public var separator: RGBAColor
        public var text: RGBAColor
        public var secondaryText: RGBAColor
        public var placeholder: RGBAColor
        /// Search icon, caret and other highlights.
        public var accent: RGBAColor
        /// Characters in a result's title that matched the query.
        public var match: RGBAColor
        public var selectionBackground: RGBAColor
        public var selectionText: RGBAColor
        public var selectionSecondaryText: RGBAColor

        /// JSON key for every color, in display order.
        public static var keys: [(name: String, path: WritableKeyPath<Colors, RGBAColor>)] {
            [
                ("background", \.background),
                ("border", \.border),
                ("separator", \.separator),
                ("text", \.text),
                ("secondaryText", \.secondaryText),
                ("placeholder", \.placeholder),
                ("accent", \.accent),
                ("match", \.match),
                ("selectionBackground", \.selectionBackground),
                ("selectionText", \.selectionText),
                ("selectionSecondaryText", \.selectionSecondaryText),
            ]
        }
    }

    public var id: String
    public var name: String
    public var appearance: Appearance
    public var colors: Colors
    public var cornerRadius: Double
    public var borderWidth: Double
    /// The file a user theme was loaded from; `nil` for built-in themes.
    public var source: URL?

    public init(
        id: String, name: String, appearance: Appearance, colors: Colors,
        cornerRadius: Double = 12, borderWidth: Double = 1, source: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.appearance = appearance
        self.colors = colors
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
        self.source = source
    }

    public var isBuiltIn: Bool { source == nil }
}
