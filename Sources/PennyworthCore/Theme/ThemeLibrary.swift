import Foundation

/// Built-in themes plus any `*.json` themes from the user's themes folder.
///
/// A theme file may extend another theme and override only some colors:
///
///     {
///       "name": "Tokyo Night Purple",
///       "extends": "tokyo-night",
///       "colors": { "accent": "#bb9af7", "border": "#bb9af7" }
///     }
///
/// Without `extends`, `appearance` and every color are required. The theme's
/// id is its file name, so `purple.json` is selected as `"theme": "purple"`.
public struct ThemeLibrary: Sendable {
    public private(set) var themes: [Theme]
    /// Human-readable reasons some theme files were skipped.
    public private(set) var problems: [String] = []

    public init(themes: [Theme] = Theme.builtIn) {
        self.themes = themes
    }

    public func theme(withID id: String) -> Theme? {
        themes.first { $0.id == id }
    }

    public static func load(from directory: URL) -> ThemeLibrary {
        var library = ThemeLibrary()
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]))?
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []

        var pending: [(url: URL, file: ThemeFile)] = []
        for url in files {
            do {
                let file = try JSONDecoder().decode(ThemeFile.self, from: Data(contentsOf: url))
                pending.append((url, file))
            } catch {
                library.problems.append("\(url.lastPathComponent): \(Self.describe(error))")
            }
        }

        // Themes may extend each other in any order; resolve until no progress.
        while !pending.isEmpty {
            var deferred: [(url: URL, file: ThemeFile)] = []
            for entry in pending {
                // Wait for a base that is itself a pending user theme. A file may extend
                // the built-in theme it overrides (tokyo-night.json extends tokyo-night).
                if let base = entry.file.extends, base != Self.id(for: entry.url),
                   pending.contains(where: { Self.id(for: $0.url) == base }) {
                    deferred.append(entry)
                    continue
                }
                do {
                    library.add(try entry.file.resolve(id: Self.id(for: entry.url), source: entry.url, in: library))
                } catch {
                    library.problems.append("\(entry.url.lastPathComponent): \(Self.describe(error))")
                }
            }
            if deferred.count == pending.count {
                for entry in deferred {
                    library.problems.append("\(entry.url.lastPathComponent): circular \"extends\"")
                }
                break
            }
            pending = deferred
        }
        return library
    }

    /// Adds a theme, replacing any existing theme with the same id.
    mutating func add(_ theme: Theme) {
        if let index = themes.firstIndex(where: { $0.id == theme.id }) {
            themes[index] = theme
        } else {
            themes.append(theme)
        }
    }

    static func id(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    private static func describe(_ error: Error) -> String {
        (error as? ThemeFile.ResolveError)?.description ?? describeLoadError(error)
    }
}

/// The on-disk theme format. Everything is optional when `extends` is set.
struct ThemeFile: Decodable {
    var name: String?
    var extends: String?
    var appearance: Theme.Appearance?
    var cornerRadius: Double?
    var borderWidth: Double?
    var colors: [String: RGBAColor]?

    enum ResolveError: Error, CustomStringConvertible {
        case unknownBase(String)
        case unknownColors([String])
        case missing([String])

        var description: String {
            switch self {
            case .unknownBase(let id): "extends unknown theme \"\(id)\""
            case .unknownColors(let names): "unknown colors: \(names.joined(separator: ", "))"
            case .missing(let names): "missing \(names.joined(separator: ", ")) (or set \"extends\")"
            }
        }
    }

    func resolve(id: String, source: URL, in library: ThemeLibrary) throws -> Theme {
        let colors = colors ?? [:]
        let known = Set(Theme.Colors.keys.map(\.name))
        let unknown = colors.keys.filter { !known.contains($0) }.sorted()
        guard unknown.isEmpty else { throw ResolveError.unknownColors(unknown) }

        if let extends {
            guard var theme = library.theme(withID: extends) else {
                throw ResolveError.unknownBase(extends)
            }
            for (name, path) in Theme.Colors.keys {
                if let color = colors[name] { theme.colors[keyPath: path] = color }
            }
            theme.id = id
            theme.name = name ?? id
            theme.appearance = appearance ?? theme.appearance
            theme.cornerRadius = cornerRadius ?? theme.cornerRadius
            theme.borderWidth = borderWidth ?? theme.borderWidth
            theme.source = source
            return theme
        }

        var missing = Theme.Colors.keys.map(\.name).filter { colors[$0] == nil }
        if appearance == nil { missing.insert("appearance", at: 0) }
        guard missing.isEmpty, let appearance else { throw ResolveError.missing(missing) }

        // Every key is present, so start from any palette and overwrite all of it.
        var resolved = Theme.tokyoNight.colors
        for (name, path) in Theme.Colors.keys {
            resolved[keyPath: path] = colors[name]!
        }
        return Theme(
            id: id, name: name ?? id, appearance: appearance, colors: resolved,
            cornerRadius: cornerRadius ?? 12, borderWidth: borderWidth ?? 1, source: source)
    }
}
