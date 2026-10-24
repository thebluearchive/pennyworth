import Foundation

/// A string prepared once for repeated fuzzy matching (e.g. an application name).
public struct MatchCandidate: Sendable, Hashable {
    public let text: String
    let keys: [UInt32]
    let bonuses: [Double]

    public init(_ text: String) {
        self.text = text
        let characters = Array(text)
        keys = characters.map(FuzzyMatcher.fold)
        var previous: Character = "/"
        bonuses = characters.map { character in
            defer { previous = character }
            return FuzzyMatcher.bonus(previous: previous, current: character)
        }
    }
}

/// A user query prepared for matching against many candidates.
public struct FuzzyQuery: Sendable, Hashable {
    public let text: String
    let keys: [UInt32]
    /// Whitespace-separated words, when there is more than one.
    let words: [[UInt32]]

    public init(_ text: String) {
        self.text = text
        keys = text.map(FuzzyMatcher.fold)
        let words = text.split(whereSeparator: \.isWhitespace)
        self.words = words.count > 1 ? words.map { $0.map(FuzzyMatcher.fold) } : []
    }

    public var isEmpty: Bool { keys.isEmpty }
}

public struct FuzzyMatch: Sendable, Equatable {
    public let score: Double
    /// Character offsets into the candidate's text that matched the query, ascending.
    public let positions: [Int]
}

/// Case- and diacritic-insensitive subsequence matcher, scored like fzy:
/// matches at word starts and consecutive runs score high, gaps cost a little.
public enum FuzzyMatcher {
    /// Matches below this, per query character, are scattered noise such as
    /// "safari" in "DisplayLink Software Uninstaller".
    public static let defaultMinimumScorePerCharacter = 0.35

    enum Score {
        static let gapLeading = -0.005
        static let gapTrailing = -0.005
        static let gapInner = -0.01
        static let consecutive = 1.0
        static let slash = 0.9
        static let word = 0.8
        static let capital = 0.7
        static let dot = 0.6
        /// Returned for a full-length match; outranks any partial match.
        static let exact = 100.0
        /// Applied when a multi-word query only matches with its words reordered.
        static let reordered = 0.9
    }

    /// Matches the whole query in order or, failing that, every word of it in any order
    /// ("wiki retired" finds "Retired Segments - Wiki").
    ///
    /// - Parameter minimumScorePerCharacter: Raise for long candidates such as web page
    ///   titles, whose many word boundaries let scattered letters score well.
    public static func match(
        _ query: FuzzyQuery, in candidate: MatchCandidate,
        minimumScorePerCharacter: Double = defaultMinimumScorePerCharacter
    ) -> FuzzyMatch? {
        if let match = match(query.keys, in: candidate, minimum: minimumScorePerCharacter) {
            return match
        }
        guard !query.words.isEmpty else { return nil }
        var score = 0.0
        var positions = Set<Int>()
        for word in query.words {
            guard let match = match(word, in: candidate, minimum: minimumScorePerCharacter) else {
                return nil
            }
            score += match.score
            positions.formUnion(match.positions)
        }
        return FuzzyMatch(score: score * Score.reordered, positions: positions.sorted())
    }

    private static func match(
        _ needle: [UInt32], in candidate: MatchCandidate, minimum: Double
    ) -> FuzzyMatch? {
        let haystack = candidate.keys
        let n = needle.count
        let m = haystack.count
        guard n > 0, n <= m, isSubsequence(needle, of: haystack) else { return nil }
        if n == m {
            return FuzzyMatch(score: Score.exact, positions: Array(0..<n))
        }

        let bonus = candidate.bonuses
        // D[i][j]: best score with needle[i] matched exactly at haystack[j].
        // M[i][j]: best score for needle[0...i] within haystack[0...j].
        var D = [Double](repeating: -.infinity, count: n * m)
        var M = [Double](repeating: -.infinity, count: n * m)

        for i in 0..<n {
            var previousScore = -Double.infinity
            let gapScore = i == n - 1 ? Score.gapTrailing : Score.gapInner
            for j in 0..<m {
                let index = i * m + j
                if needle[i] == haystack[j] {
                    var score = -Double.infinity
                    if i == 0 {
                        score = Double(j) * Score.gapLeading + bonus[j]
                    } else if j > 0 {
                        let diagonal = (i - 1) * m + (j - 1)
                        score = max(M[diagonal] + bonus[j], D[diagonal] + Score.consecutive)
                    }
                    D[index] = score
                    previousScore = max(score, previousScore + gapScore)
                } else {
                    previousScore += gapScore
                }
                M[index] = previousScore
            }
        }

        let score = M[n * m - 1]
        guard score >= minimum * Double(n) else { return nil }

        // Walk back through the matrices to recover which characters matched.
        var positions = [Int](repeating: 0, count: n)
        var matchRequired = false
        var j = m - 1
        for i in stride(from: n - 1, through: 0, by: -1) {
            while j >= 0 {
                let index = i * m + j
                if D[index] != -.infinity, matchRequired || D[index] == M[index] {
                    matchRequired = i > 0 && j > 0
                        && M[index] == D[(i - 1) * m + (j - 1)] + Score.consecutive
                    positions[i] = j
                    j -= 1
                    break
                }
                j -= 1
            }
        }

        return FuzzyMatch(score: score, positions: positions)
    }

    private static func isSubsequence(_ needle: [UInt32], of haystack: [UInt32]) -> Bool {
        var remaining = needle[...]
        for key in haystack where key == remaining.first {
            remaining = remaining.dropFirst()
            if remaining.isEmpty { return true }
        }
        return remaining.isEmpty
    }

    /// Folds one character to a comparison key, ignoring case, diacritics and width.
    static func fold(_ character: Character) -> UInt32 {
        let folded = String(character).folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        return folded.unicodeScalars.first?.value ?? 0
    }

    static func bonus(previous: Character, current: Character) -> Double {
        guard current.isLetter || current.isNumber else { return 0 }
        switch previous {
        case "/": return Score.slash
        case ".": return Score.dot
        default:
            if !(previous.isLetter || previous.isNumber) { return Score.word }
            if previous.isLowercase && current.isUppercase { return Score.capital }
            return 0
        }
    }
}
