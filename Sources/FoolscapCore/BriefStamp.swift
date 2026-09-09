import Foundation

/// The build-time stamp `brief.md` carries on its first line (DESIGN.md → "The panel":
/// Brief "carries the freshness stamp"; → Trust → "Freshness"): a comment of the form
/// `<!-- built: <ISO8601-local> -->`, written by the morning routine (ticket C1).
///
/// Acting on a stale plan without knowing is the failure mode this guards against
/// (ROADMAP.md → D1), so a missing or malformed stamp must read as a clear "unknown," never
/// a fabricated time. Parsing and display formatting live here, in `FoolscapCore`, so both
/// are unit-testable without a `WKWebView` — the app layer (`DashboardRenderer`) only calls
/// `parse` and `displayString`.
public enum BriefStamp: Equatable, Sendable {
    /// The instant `brief.md` was built.
    case known(Date)
    /// The first line was missing the stamp, or it didn't parse. Never invented.
    case unknown

    private static let prefix = "<!-- built: "
    private static let suffix = " -->"

    /// Parses the stamp from `markdown`'s first line. Anything else — no first line, the
    /// wrong comment shape, or an unparseable date inside it — is `.unknown`.
    public static func parse(_ markdown: String) -> BriefStamp {
        guard let iso = isoPayload(of: markdown), let date = isoFormatter.date(from: iso) else {
            return .unknown
        }
        return .known(date)
    }

    /// `markdown` with its build-stamp comment line removed, so the Brief's rendered body
    /// doesn't also show the raw `<!-- built: ... -->` line as text (an HTML comment isn't
    /// markup `MarkdownRenderer` recognises, so left in place it would render escaped,
    /// verbatim). Stripped whether or not the date inside parses — a malformed stamp is
    /// still a stamp line, not brief prose. Markdown missing the line entirely is returned
    /// unchanged.
    public static func stripStampLine(from markdown: String) -> String {
        guard isoPayload(of: markdown) != nil else { return markdown }
        guard let newlineIndex = markdown.firstIndex(of: "\n") else { return "" }
        return String(markdown[markdown.index(after: newlineIndex)...])
    }

    /// The first line's text between `prefix` and `suffix`, if it has that shape at all —
    /// regardless of whether what's between them is a valid date.
    private static func isoPayload(of markdown: String) -> String? {
        let firstLine = markdown.prefix(while: { $0 != "\n" })
        guard firstLine.hasPrefix(prefix), firstLine.hasSuffix(suffix) else { return nil }
        return String(firstLine.dropFirst(prefix.count).dropLast(suffix.count))
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// "built 7:58am" (DESIGN.md's own example) for a known instant; a clear stale/unknown
    /// state otherwise — never a guessed time. `timeZone` defaults to the viewer's own, so
    /// the displayed hour matches the wall clock the user reads it against.
    public func displayString(timeZone: TimeZone = .current) -> String {
        switch self {
        case .known(let date):
            return "built \(Self.timeFormatter(timeZone: timeZone).string(from: date))"
        case .unknown:
            return "build time unknown"
        }
    }

    private static func timeFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        // Fixed locale so "am"/"pm" render lowercase regardless of the user's own locale —
        // matching DESIGN.md's literal example, not a locale-formatted alternative.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mma"
        formatter.amSymbol = "am"
        formatter.pmSymbol = "pm"
        return formatter
    }
}
