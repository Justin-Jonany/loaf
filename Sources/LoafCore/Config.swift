import Foundation

/// The documented subset of `~/.config/loaf/config.toml`.
///
/// A small hand-rolled reader over the flat `key = value` / `[section]` shape used by
/// `config.example.toml` — not a general TOML parser. Every key is optional; a missing
/// file, missing key, or unparsable value all fall back to the documented default.
public struct Config: Sendable, Equatable {
    public static let defaultTheme = "frosted"
    public static let defaultStartMode = "preview"
    public static let defaultSoonWithinDays = 2
    public static let defaultWeekStarts = "monday"

    public var vault: String?
    public var theme: String
    public var startMode: String
    public var soonWithinDays: Int
    public var weekStarts: String

    public init(
        vault: String? = nil,
        theme: String = Config.defaultTheme,
        startMode: String = Config.defaultStartMode,
        soonWithinDays: Int = Config.defaultSoonWithinDays,
        weekStarts: String = Config.defaultWeekStarts
    ) {
        self.vault = vault
        self.theme = theme
        self.startMode = startMode
        self.soonWithinDays = soonWithinDays
        self.weekStarts = weekStarts
    }

    public static var defaultPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/loaf/config.toml")
    }

    /// Loads `path`, if it exists. A missing file is not an error — it just means defaults.
    public static func load(from path: URL = Config.defaultPath) -> Config {
        guard let contents = try? String(contentsOf: path, encoding: .utf8) else {
            return Config()
        }
        return parse(contents)
    }

    static func parse(_ text: String) -> Config {
        var config = Config()
        var section = ""

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            if line.hasPrefix("["), line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast())
                continue
            }

            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[line.startIndex..<equals].trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            if let hash = value.firstIndex(of: "#") {
                value = String(value[value.startIndex..<hash]).trimmingCharacters(in: .whitespaces)
            }
            value = unquote(value)

            switch (section, key) {
            case ("", "vault"): config.vault = value
            case ("", "theme"): config.theme = value
            case ("", "start_mode"): config.startMode = value
            case ("dates", "soon_within_days"): if let n = Int(value) { config.soonWithinDays = n }
            case ("dates", "week_starts"): config.weekStarts = value
            default: break // Undocumented keys (opacity, hotkey, ...) are left for a later slice.
            }
        }
        return config
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else { return value }
        return String(value.dropFirst().dropLast())
    }

    // MARK: - Writing (live theme switching — DECISIONS.md 2026-09-11)

    public enum ConfigError: Error {
        case writeFailed(URL, errno: Int32)
    }

    /// Writes `theme` into the config file at `path`, preserving every other line
    /// (including comments and the `[dates]` section) — the menu-bar theme picker's
    /// writing side. A missing file is created containing just the theme key.
    public static func setTheme(_ theme: String, at path: URL = Config.defaultPath) throws {
        let existing = (try? String(contentsOf: path, encoding: .utf8)) ?? ""
        try writeAtomically(settingTheme(theme, in: existing), to: path)
    }

    /// Replaces an existing top-level `theme = "..."` line in place, or inserts one if
    /// absent. Tracks `[section]` headers the same way `parse` does so a `theme` key
    /// nested under some other section is never mistaken for the top-level one. Splitting
    /// and rejoining on "\n" (mirroring `parse`'s own line-splitting) round-trips every
    /// other line — including a file with no trailing newline — untouched.
    static func settingTheme(_ theme: String, in text: String) -> String {
        let newLine = "theme = \"\(theme)\""
        guard !text.isEmpty else { return newLine + "\n" }

        var lines = text.components(separatedBy: "\n")
        var section = ""
        for (i, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("["), line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast())
                continue
            }
            guard !line.isEmpty, !line.hasPrefix("#"), let equals = line.firstIndex(of: "=") else { continue }
            let key = line[line.startIndex..<equals].trimmingCharacters(in: .whitespaces)
            if section.isEmpty, key == "theme" {
                lines[i] = newLine
                return lines.joined(separator: "\n")
            }
        }

        // No existing top-level `theme` key: insert before the first section header so it
        // stays top-level (matching config.example.toml's layout); with no sections,
        // append at the end, ahead of the trailing blank line a final newline leaves behind.
        if let sectionIndex = lines.firstIndex(where: {
            let l = $0.trimmingCharacters(in: .whitespaces)
            return l.hasPrefix("[") && l.hasSuffix("]")
        }) {
            lines.insert(newLine, at: sectionIndex)
        } else if lines.last == "" {
            lines.insert(newLine, at: lines.count - 1)
        } else {
            lines.append(newLine)
        }
        return lines.joined(separator: "\n")
    }

    /// Temp file + `rename(2)`, mirroring `Vault.writeAtomically`'s pattern so a reader
    /// never observes a half-written config file. Not routed through `Vault` itself: the
    /// config file lives outside the vault (`~/.config/loaf/`), so none of `Vault`'s
    /// self-write tracking applies here.
    private static func writeAtomically(_ content: String, to path: URL) throws {
        let directory = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let tempURL = directory.appendingPathComponent(".\(path.lastPathComponent).\(UUID().uuidString).tmp")
        try content.write(to: tempURL, atomically: false, encoding: .utf8)

        let result = tempURL.path.withCString { tempPath in
            path.path.withCString { destPath in
                rename(tempPath, destPath)
            }
        }
        guard result == 0 else {
            let code = errno
            try? FileManager.default.removeItem(at: tempURL)
            throw ConfigError.writeFailed(path, errno: code)
        }
    }
}
