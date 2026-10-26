import Foundation

/// The `.command` file a terminal app runs for `> command`. Terminal, iTerm and Ghostty all
/// open these, so running a command needs no permission to control another app.
public enum TerminalScript {
    /// Runs `command` in the user's interactive login shell, so their PATH, aliases and
    /// version managers apply, then leaves that shell open in the window.
    public static func contents(running command: String) -> String {
        let quoted = shellQuoted(command)
        // `clear` hides the line Terminal echoes to start the script.
        return """
            #!/bin/sh
            rm -f "$0"
            cd "$HOME" 2>/dev/null
            clear 2>/dev/null
            shell="${SHELL:-/bin/zsh}"
            printf '\\033[2m$ %s\\033[0m\\n' \(quoted)
            "$shell" -l -i -c \(quoted)
            exec "$shell" -l

            """
    }

    /// Writes the script as an executable file in `directory`. It deletes itself once it starts.
    public static func write(
        running command: String, in directory: URL = FileManager.default.temporaryDirectory
    ) throws -> URL {
        let url = directory.appendingPathComponent("pennyworth-\(UUID().uuidString).command")
        try Data(contents(running: command).utf8).write(to: url, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    /// `it's` → `'it'\''s'`
    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
