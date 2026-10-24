import Foundation

public struct Application: Sendable, Hashable {
    public let url: URL
    /// Localized name as Finder shows it, e.g. "System Settings".
    public let name: String
    public let bundleIdentifier: String?
    /// Other names the app answers to (file name, CFBundleName...), excluding `name`.
    public let alternateNames: [String]
}

/// Finds `.app` bundles in a set of folders.
public struct ApplicationScanner: Sendable {
    public struct Location: Sendable, Hashable {
        public let url: URL
        /// How many folder levels to descend. 1 = only direct children.
        public let depth: Int

        public init(_ url: URL, depth: Int) {
            self.url = url
            self.depth = depth
        }

        public init(path: String, depth: Int) {
            self.init(URL(fileURLWithPath: (path as NSString).expandingTildeInPath), depth: depth)
        }
    }

    /// Roughly the folders Alfred indexes by default.
    public static let defaultLocations: [Location] = [
        Location(path: "/Applications", depth: 2),
        Location(path: "/System/Applications", depth: 2),
        Location(path: "~/Applications", depth: 3),
        Location(path: "/System/Library/CoreServices/Applications", depth: 1),
        Location(path: "/System/Library/CoreServices/Finder.app", depth: 0),
    ]

    public var locations: [Location]

    public init(locations: [Location] = Self.defaultLocations) {
        self.locations = locations
    }

    public func scan() -> [Application] {
        var seen = Set<String>()
        var applications: [Application] = []
        for location in locations {
            for url in bundles(in: location) {
                // Symlinks (Safari lives in a cryptex) and overlapping locations
                // can yield the same bundle twice.
                let canonical = url.resolvingSymlinksInPath().standardizedFileURL.path
                guard seen.insert(canonical).inserted,
                      let app = Self.application(at: url) else { continue }
                applications.append(app)
            }
        }
        return applications
    }

    private func bundles(in location: Location) -> [URL] {
        if location.url.pathExtension == "app" {
            return FileManager.default.fileExists(atPath: location.url.path) ? [location.url] : []
        }
        var found: [URL] = []
        collect(in: location.url, depth: location.depth, into: &found)
        return found
    }

    private func collect(in folder: URL, depth: Int, into found: inout [URL]) {
        guard depth > 0,
              let entries = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isDirectoryKey])
        else { return }

        // Only skip dot-files: the /Applications/Safari.app symlink has the hidden flag.
        for entry in entries where !entry.lastPathComponent.hasPrefix(".") {
            if entry.pathExtension == "app" {
                found.append(entry)
            } else if depth > 1, Self.isDirectory(entry) {
                collect(in: entry, depth: depth - 1, into: &found)
            }
        }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    static func application(at url: URL) -> Application? {
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        // Read the plist directly: Bundle(url:) caches forever and goes stale on app updates.
        let info = NSDictionary(contentsOf: infoURL) as? [String: Any] ?? [:]

        let fileName = url.deletingPathExtension().lastPathComponent
        var displayName = FileManager.default.displayName(atPath: url.path)
        if displayName.hasSuffix(".app") {
            displayName = String(displayName.dropLast(4))
        }
        let name = displayName.isEmpty ? fileName : displayName

        var alternates: [String] = []
        var seen: Set<String> = [name.lowercased()]
        for candidate in [fileName, info["CFBundleDisplayName"] as? String, info["CFBundleName"] as? String] {
            guard let candidate, !candidate.isEmpty,
                  seen.insert(candidate.lowercased()).inserted else { continue }
            alternates.append(candidate)
        }

        return Application(
            url: url, name: name,
            bundleIdentifier: info["CFBundleIdentifier"] as? String,
            alternateNames: alternates)
    }
}
