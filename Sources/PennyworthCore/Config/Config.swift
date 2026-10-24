import Foundation

/// User settings, stored as JSON in `~/.config/pennyworth/config.json`.
/// Every key is optional; missing keys take their defaults.
public struct Config: Sendable, Equatable, Codable {
    /// Id of the active theme (built-in or a file name in the themes folder).
    public var theme = Theme.defaultID
    /// Global shortcut that toggles the launcher, e.g. `"option+space"`.
    public var hotkey = "option+space"
    /// Rows shown before the result list scrolls.
    public var maxVisibleResults = 8
    /// Extra folders to search for applications, besides the standard ones.
    public var applicationFolders: [String] = []
    /// Include Firefox bookmarks in results.
    public var firefoxBookmarks = true
    /// Word to type before a bookmark search (`b vento`). Empty mixes bookmarks into every search.
    public var bookmarksKeyword = "b"

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case theme, hotkey, maxVisibleResults, applicationFolders, firefoxBookmarks, bookmarksKeyword
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Config()
        theme = try container.decodeIfPresent(String.self, forKey: .theme) ?? defaults.theme
        hotkey = try container.decodeIfPresent(String.self, forKey: .hotkey) ?? defaults.hotkey
        maxVisibleResults = try container.decodeIfPresent(Int.self, forKey: .maxVisibleResults)
            ?? defaults.maxVisibleResults
        applicationFolders = try container.decodeIfPresent([String].self, forKey: .applicationFolders)
            ?? defaults.applicationFolders
        firefoxBookmarks = try container.decodeIfPresent(Bool.self, forKey: .firefoxBookmarks)
            ?? defaults.firefoxBookmarks
        bookmarksKeyword = try container.decodeIfPresent(String.self, forKey: .bookmarksKeyword)
            ?? defaults.bookmarksKeyword
    }

    /// `bookmarksKeyword` as a provider keyword: `nil` when bookmarks aren't gated.
    public var bookmarksKeywordIfSet: String? {
        let keyword = bookmarksKeyword.trimmingCharacters(in: .whitespaces)
        return keyword.isEmpty ? nil : keyword
    }
}

public enum Paths {
    /// `$XDG_CONFIG_HOME/pennyworth`, defaulting to `~/.config/pennyworth`.
    public static var configDirectory: URL {
        let base = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].flatMap {
            $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true)
        } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        return base.appendingPathComponent("pennyworth", isDirectory: true)
    }

    public static var configFile: URL { configDirectory.appendingPathComponent("config.json") }

    /// Data the app keeps for itself: `$XDG_STATE_HOME/pennyworth` if set, otherwise
    /// `~/Library/Application Support/Pennyworth`.
    public static var stateDirectory: URL {
        if let state = ProcessInfo.processInfo.environment["XDG_STATE_HOME"], !state.isEmpty {
            return URL(fileURLWithPath: state, isDirectory: true).appendingPathComponent("pennyworth")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Pennyworth", isDirectory: true)
    }

    public static var historyFile: URL { stateDirectory.appendingPathComponent("knowledge.json") }
    public static var themesDirectory: URL { configDirectory.appendingPathComponent("themes", isDirectory: true) }
}

public struct ConfigStore: Sendable {
    public let url: URL

    public init(url: URL = Paths.configFile) {
        self.url = url
    }

    /// Returns defaults when the file doesn't exist; throws if it exists but is invalid.
    public func load() throws -> Config {
        guard FileManager.default.fileExists(atPath: url.path) else { return Config() }
        do {
            return try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
        } catch {
            throw ConfigError(file: url, reason: describeLoadError(error))
        }
    }

    /// Writes `config`, keeping any keys in the existing file that `Config` doesn't know.
    public func save(_ config: Config) throws {
        var object: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            object = existing
        }
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config))
        for (key, value) in encoded as? [String: Any] ?? [:] {
            object[key] = value
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try (data + Data("\n".utf8)).write(to: url, options: .atomic)
    }
}

public struct ConfigError: Error, CustomStringConvertible {
    public let file: URL
    public let reason: String

    public init(file: URL, reason: String) {
        self.file = file
        self.reason = reason
    }

    public var description: String { "\(file.lastPathComponent): \(reason)" }
}
