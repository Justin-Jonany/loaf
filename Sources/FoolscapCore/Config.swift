import Foundation

/// The documented subset of `~/.config/foolscap/config.toml`.
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
            .appendingPathComponent(".config/foolscap/config.toml")
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
}
