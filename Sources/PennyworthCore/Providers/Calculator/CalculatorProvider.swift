import Foundation

/// Answers arithmetic (`= 24*7`, or `24*7` when it contains an operator) and unit
/// conversions (`3 GB in MB`). ↩ copies the number, ⌘↩ the whole line.
public struct CalculatorProvider: SearchProvider {
    /// Above any name match: a query that parses as math is meant as math.
    static let score = 1000.0

    private let locale: Locale

    /// - Parameter locale: For displaying numbers. Copied numbers are always plain
    ///   (`1234.5`), so they paste anywhere.
    public init(locale: Locale = .current) {
        self.locale = locale
    }

    public func search(_ query: SearchQuery) async -> [SearchResult] {
        var text = query.text
        let explicit = text.hasPrefix("=")
        if explicit { text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces) }
        guard !text.isEmpty else { return [] }

        if let evaluation = try? Calculator.evaluate(text), explicit || evaluation.operationCount > 0 {
            let answer = Self.plain(evaluation.value)
            return [SearchResult(
                id: "calculator", title: format(evaluation.value),
                subtitle: "\(text) · ↩ copy · ⌘↩ copy “\(text) = \(answer)”",
                icon: .symbol("equal.circle"), score: Self.score,
                action: .copyToClipboard(answer),
                alternateAction: .copyToClipboard("\(text) = \(answer)"),
                autocomplete: "= \(answer)", isLearnable: false)]
        }

        if let conversion = UnitConverter.convert(text) {
            let answer = Self.plain(conversion.result)
            let line = "\(Self.plain(conversion.value)) \(conversion.unit) = \(answer) \(conversion.targetUnit)"
            return [SearchResult(
                id: "conversion", title: "\(format(conversion.result)) \(conversion.targetUnit)",
                subtitle: "\(format(conversion.value)) \(conversion.unit) · ↩ copy \(answer) · ⌘↩ copy “\(line)”",
                icon: .symbol("arrow.left.arrow.right.circle"), score: Self.score,
                action: .copyToClipboard(answer), alternateAction: .copyToClipboard(line),
                autocomplete: "\(answer) \(conversion.targetUnit)", isLearnable: false)]
        }
        return []
    }

    /// For display: grouped, in the user's locale, scientific when very large or small.
    func format(_ value: Double) -> String {
        Self.format(value, locale: locale, grouping: true)
    }

    /// For copying: `1234.5`, never grouped or localized.
    static func plain(_ value: Double) -> String {
        format(value, locale: Locale(identifier: "en_US_POSIX"), grouping: false)
    }

    private static func format(_ value: Double, locale: Locale, grouping: Bool) -> String {
        let magnitude = abs(value)
        if magnitude != 0, magnitude >= 1e15 || magnitude < 1e-6 {
            return value.formatted(
                .number.notation(.scientific).precision(.significantDigits(1...10)).locale(locale))
        }
        return value.formatted(
            .number.precision(.significantDigits(1...12))
                .grouping(grouping ? .automatic : .never).locale(locale))
    }
}
