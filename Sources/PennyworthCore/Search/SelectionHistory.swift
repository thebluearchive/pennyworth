import Foundation
import os

/// Remembers which result was picked for which query, so it ranks higher next time:
/// pick Chrome after typing `c` a few times and `c` brings Chrome to the top.
///
/// Picks for the same query count fully; picks for a longer query that starts with the
/// one typed (`chr` when typing `c`) count half. Old picks fade with a 60-day half-life.
public final class SelectionHistory: Sendable {
    struct Pick: Codable, Sendable, Equatable {
        /// Number of picks, decayed as of `lastPicked`.
        var weight: Double
        var lastPicked: Date
    }

    private struct Storage: Codable {
        var version = 1
        /// Normalized query → result id → pick.
        var picks: [String: [String: Pick]]
    }

    /// Boost for a single pick; repeated picks add less and less.
    static let boostPerPick = 1.5
    static let prefixWeight = 0.5
    static let halfLife: TimeInterval = 60 * 24 * 60 * 60
    /// Oldest and least-used pairs are dropped beyond this.
    static let capacity = 5000
    static let maximumQueryLength = 64

    private let file: URL?
    private let picks: OSAllocatedUnfairLock<[String: [String: Pick]]>

    /// Loads history from `file` if it exists; `nil` keeps it in memory only.
    public init(file: URL?) {
        self.file = file
        let stored = file
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder.history.decode(Storage.self, from: $0) }
        picks = OSAllocatedUnfairLock(initialState: stored?.picks ?? [:])
    }

    /// Records that `resultID` was picked after typing `query`.
    public func record(query: String, resultID: String, at date: Date = Date()) {
        let query = Self.normalize(query)
        guard !query.isEmpty else { return }
        picks.withLock { picks in
            var pick = picks[query]?[resultID] ?? Pick(weight: 0, lastPicked: date)
            pick.weight = Self.decayed(pick, at: date) + 1
            pick.lastPicked = date
            picks[query, default: [:]][resultID] = pick
            Self.prune(&picks, at: date)
        }
    }

    /// Score to add to each result id for `query`. Empty if nothing was learned.
    public func boosts(for query: String, at date: Date = Date()) -> [String: Double] {
        let query = Self.normalize(query)
        guard !query.isEmpty else { return [:] }
        let totals = picks.withLock { picks in
            var totals: [String: Double] = [:]
            for (stored, results) in picks {
                let weight = stored == query ? 1 : stored.hasPrefix(query) ? Self.prefixWeight : 0
                guard weight > 0 else { continue }
                for (id, pick) in results {
                    totals[id, default: 0] += weight * Self.decayed(pick, at: date)
                }
            }
            return totals
        }
        return totals.mapValues { Self.boostPerPick * log2(1 + $0) }
    }

    public var isEmpty: Bool { picks.withLock { $0.isEmpty } }

    /// Number of (query, result) pairs remembered.
    var pairCount: Int { picks.withLock { $0.values.reduce(0) { $0 + $1.count } } }

    public func clear() {
        picks.withLock { $0 = [:] }
    }

    /// Writes the history to its file, if it has one.
    public func save() throws {
        guard let file else { return }
        let storage = Storage(picks: picks.withLock { $0 })
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.history.encode(storage).write(to: file, options: .atomic)
    }

    static func normalize(_ query: String) -> String {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        return String(words.joined(separator: " ").prefix(maximumQueryLength))
    }

    private static func decayed(_ pick: Pick, at date: Date) -> Double {
        let age = max(date.timeIntervalSince(pick.lastPicked), 0)
        return pick.weight * pow(0.5, age / halfLife)
    }

    private static func prune(_ picks: inout [String: [String: Pick]], at date: Date) {
        let count = picks.values.reduce(0) { $0 + $1.count }
        guard count > capacity else { return }
        // Least used first; among equals, least recently picked first.
        let ranked = picks.flatMap { query, results in
            results.map { (query: query, id: $0.key, weight: decayed($0.value, at: date), last: $0.value.lastPicked) }
        }.sorted { ($0.weight, $0.last) < ($1.weight, $1.last) }
        for entry in ranked.prefix(count - capacity) {
            picks[entry.query]?[entry.id] = nil
            if picks[entry.query]?.isEmpty == true { picks[entry.query] = nil }
        }
    }
}

private extension JSONEncoder {
    static var history: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var history: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
