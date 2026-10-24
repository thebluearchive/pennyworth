import Darwin
import Foundation

public struct Bookmark: Sendable, Hashable {
    public let title: String
    public let url: URL
    /// Folder names from the top, e.g. `["Bookmarks Toolbar", "Dev"]`.
    public let folders: [String]
    public let tags: [String]
    /// Firefox's per-bookmark keyword, if one is set.
    public let keyword: String?
}

public enum FirefoxBookmarks {
    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Firefox", isDirectory: true)
    }

    /// Profile folders that have a bookmarks database, default profiles first.
    public static func profiles(in directory: URL = defaultDirectory) -> [URL] {
        var ordered: [String] = []
        let installs = INIFile(directory.appendingPathComponent("installs.ini"))
        let profiles = INIFile(directory.appendingPathComponent("profiles.ini"))

        // installs.ini (and [Install…] in profiles.ini) name each Firefox install's default.
        for (_, keys) in installs.sections { keys["Default"].map { ordered.append($0) } }
        for (name, keys) in profiles.sections where name.hasPrefix("Install") {
            keys["Default"].map { ordered.append($0) }
        }
        let listed = profiles.sections.filter { $0.name.hasPrefix("Profile") }.map(\.keys)
        for keys in listed where keys["Default"] == "1" { keys["Path"].map { ordered.append($0) } }
        for keys in listed { keys["Path"].map { ordered.append($0) } }
        // Anything in Profiles/ that the ini files don't mention.
        let folder = directory.appendingPathComponent("Profiles")
        let extra = (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.sorted() ?? []
        ordered += extra.map { "Profiles/\($0)" }

        var seen = Set<String>()
        return ordered.compactMap { path in
            let url = path.hasPrefix("/")
                ? URL(fileURLWithPath: path) : directory.appendingPathComponent(path)
            let key = url.standardizedFileURL.path
            guard seen.insert(key).inserted,
                  FileManager.default.fileExists(atPath: url.appendingPathComponent("places.sqlite").path)
            else { return nil }
            return url
        }
    }

    /// Reads a profile's bookmarks. Firefox keeps `places.sqlite` locked while it runs,
    /// so this reads a copy-on-write clone (instant on APFS, even for large databases).
    public static func read(profile: URL) throws -> [Bookmark] {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("pennyworth-places-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        // The WAL holds recent changes that Firefox hasn't merged into the database yet.
        for name in ["places.sqlite", "places.sqlite-wal"] {
            let source = profile.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            let target = scratch.appendingPathComponent(name)
            guard copyfile(source.path, target.path, nil, copyfile_flags_t(COPYFILE_CLONE)) == 0 else {
                throw SQLiteError(message: "couldn't copy \(name): \(String(cString: strerror(errno)))")
            }
        }
        return try read(database: scratch.appendingPathComponent("places.sqlite"))
    }

    private static let rootNames = [
        "menu________": "Bookmarks Menu",
        "toolbar_____": "Bookmarks Toolbar",
        "unfiled_____": "Other Bookmarks",
        "mobile______": "Mobile Bookmarks",
    ]

    static func read(database url: URL) throws -> [Bookmark] {
        let database = try SQLiteDatabase(url)

        struct Folder {
            let parent: Int64
            let title: String
            let guid: String
        }
        var folders: [Int64: Folder] = [:]
        try database.query("SELECT id, parent, IFNULL(title, ''), guid FROM moz_bookmarks WHERE type = 2") { row in
            folders[row.int(0)] = Folder(parent: row.int(1), title: row.text(2) ?? "", guid: row.text(3) ?? "")
        }
        let tagsRoot = folders.first { $0.value.guid == "tags________" }?.key

        var keywords: [Int64: String] = [:]
        try database.query("SELECT place_id, keyword FROM moz_keywords") { row in
            if let keyword = row.text(1) { keywords[row.int(0)] = keyword }
        }

        struct Row {
            let place: Int64
            let parent: Int64
            let title: String?
            let url: String
        }
        var rows: [Row] = []
        var tags: [Int64: [String]] = [:]
        try database.query("""
            SELECT b.fk, b.parent, IFNULL(NULLIF(b.title, ''), p.title), p.url
            FROM moz_bookmarks b JOIN moz_places p ON p.id = b.fk
            WHERE b.type = 1
            ORDER BY b.parent, b.position
            """) { row in
            let entry = Row(place: row.int(0), parent: row.int(1), title: row.text(2), url: row.text(3) ?? "")
            // Each tag is a folder under the tags root holding a copy of the bookmark.
            if let tagsRoot, let folder = folders[entry.parent], folder.parent == tagsRoot {
                tags[entry.place, default: []].append(folder.title)
            } else {
                rows.append(entry)
            }
        }

        var paths: [Int64: [String]?] = [:]
        func path(of id: Int64) -> [String]? {
            if let cached = paths[id] { return cached }
            guard let folder = folders[id] else { return nil }
            let result: [String]?
            if folder.guid == "root________" {
                result = []
            } else if id == tagsRoot {
                result = nil
            } else {
                result = path(of: folder.parent).map { $0 + [rootNames[folder.guid] ?? folder.title] }
            }
            paths[id] = result
            return result
        }

        return rows.compactMap { row in
            guard let url = URL(string: row.url), let scheme = url.scheme?.lowercased(),
                  !["place", "javascript"].contains(scheme),
                  let folders = path(of: row.parent) else { return nil }
            let title = row.title.flatMap { $0.isEmpty ? nil : $0 } ?? url.host ?? row.url
            return Bookmark(
                title: title, url: url, folders: folders,
                tags: tags[row.place] ?? [], keyword: keywords[row.place])
        }
    }
}

/// Just enough of the INI format for Firefox's profiles.ini and installs.ini.
struct INIFile {
    private(set) var sections: [(name: String, keys: [String: String])] = []

    init(_ url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        for line in text.split(whereSeparator: \.isNewline) {
            let line = line.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("["), line.hasSuffix("]") {
                sections.append((String(line.dropFirst().dropLast()), [:]))
            } else if let equals = line.firstIndex(of: "="), !sections.isEmpty {
                let key = String(line[..<equals]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
                sections[sections.count - 1].keys[key] = value
            }
        }
    }
}
