import Foundation

/// The morning routine's "needs a decision" / "failed" signal (ROADMAP.md → Wave 3 →
/// D2; DECISIONS.md 2026-08-23): a sidecar dotfile, `.routine-signal.md`, at the vault
/// root. Its absence is the clear-day state — DESIGN.md → Trust is explicit that a clear
/// day produces no interruption. `VaultWatcher` already delivers change events for it
/// (a dotfile still matches the `.md` filter — see `VaultWatcher`), and `Vault.notePaths()`
/// already skips it, so it never shows up as a note in the panel.
///
///     status: needs-decision
///     at: 2026-08-23T06:02:14-07:00
///     reason: one-line summary of what needs a call
///     questions:
///       - the first concrete question to ask
///       - a second one, if there is one
///
/// or:
///
///     status: failed
///     at: 2026-08-23T06:02:14-07:00
///     reason: one line describing what failed
public struct RoutineSignal: Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        case needsDecision = "needs-decision"
        case failed
        /// The file is present but its content doesn't parse into a recognized signal
        /// (no `status:` line, or a value that isn't `needs-decision`/`failed`). This is
        /// deliberately not treated the same as an absent file: a signal file that exists
        /// but is broken almost always means the routine's write got interrupted or
        /// corrupted, which is exactly the kind of failure DESIGN.md → Trust says must be
        /// loud, not silently swallowed. `SignalNudge.decide` turns this into a failure
        /// nudge.
        case malformed
    }

    public var status: Status
    public var at: Date?
    public var reason: String
    public var questions: [String]

    public init(status: Status, at: Date? = nil, reason: String = "", questions: [String] = []) {
        self.status = status
        self.at = at
        self.reason = reason
        self.questions = questions
    }

    /// Parses `2026-08-23T06:02:14-07:00` — the same ISO 8601 + offset shape `brief.md`'s
    /// build stamp uses. Not a `CalendarDate`: this timestamp is "when the routine ran,"
    /// an instant, not a date-only `@due`/`✓done` value, so none of the DST hazards that
    /// rule out `Date` for due dates apply here.
    private static let timestampFormatter = ISO8601DateFormatter()

    /// Parses the raw contents of `.routine-signal.md`.
    ///
    /// `nil` for blank/whitespace-only text — the caller's contract is that this also
    /// covers an absent file (it never reads one that doesn't exist), so both cases mean
    /// the same thing: a clear day, nothing to see.
    ///
    /// Non-blank text always produces a value, even when it doesn't parse — see
    /// `Status.malformed`. Unrecognized top-level keys and, within `questions:`, anything
    /// that isn't a `- ` list item are ignored rather than failing the whole parse, the
    /// same lenient-token philosophy `TaskBlock.applyMetadata` uses.
    public static func parse(_ text: String) -> RoutineSignal? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        var statusRaw: String?
        var atRaw: String?
        var reason = ""
        var questions: [String] = []
        var inQuestions = false

        for rawLine in text.components(separatedBy: "\n") {
            guard !rawLine.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let isIndented = rawLine.first == " " || rawLine.first == "\t"

            if isIndented, inQuestions {
                let item = rawLine.trimmingCharacters(in: .whitespaces)
                if item.hasPrefix("- ") {
                    questions.append(String(item.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                    continue
                }
            }
            inQuestions = false

            guard let colon = rawLine.firstIndex(of: ":") else { continue }
            let key = rawLine[rawLine.startIndex..<colon].trimmingCharacters(in: .whitespaces)
            let value = String(rawLine[rawLine.index(after: colon)...]).trimmingCharacters(in: .whitespaces)

            switch key {
            case "status": statusRaw = value
            case "at": atRaw = value
            case "reason": reason = value
            case "questions": inQuestions = true // consume the indented "- " lines that follow
            default: break // forward-compatible with a field this parser doesn't know yet
            }
        }

        let at = atRaw.flatMap { timestampFormatter.date(from: $0) }

        guard let statusRaw, let status = Status(rawValue: statusRaw) else {
            return RoutineSignal(status: .malformed, at: at, reason: reason, questions: questions)
        }
        return RoutineSignal(status: status, at: at, reason: reason, questions: questions)
    }
}

/// The nudge the app should fire for a given signal — the pure decision the app-side
/// notification wiring (`Sources/Foolscap`) reads and acts on. Kept separate from
/// `RoutineSignal` itself so the mapping ("what does a `failed` status *mean* for the
/// user") stays a one-line, independently testable rule.
public enum SignalNudge: Equatable, Sendable {
    /// Clear day — the app posts nothing (DESIGN.md → Trust: silent on a clear day).
    case none
    /// A normal nudge: today needs a call. `questions` is 0-3 short prompts a person can
    /// answer in Claude Code (DESIGN.md → "The daily loop": the conversation happens
    /// there, not in the app).
    case decision(reason: String, questions: [String])
    /// A distinct, louder nudge: the run failed rather than producing a stale-but-normal-
    /// looking brief (DESIGN.md → Trust: "Failure is loud"). Also fired for a malformed
    /// signal file — see `RoutineSignal.Status.malformed`.
    case failure(reason: String)

    /// `signal == nil` is the clear-day/absent-file state → `.none`. Every other case maps
    /// 1:1 from `RoutineSignal.status`, with `.malformed` folded into `.failure` so a
    /// broken signal is loud rather than silently dropped.
    public static func decide(for signal: RoutineSignal?) -> SignalNudge {
        guard let signal else { return .none }
        switch signal.status {
        case .needsDecision:
            return .decision(reason: signal.reason, questions: signal.questions)
        case .failed:
            return .failure(reason: signal.reason)
        case .malformed:
            return .failure(
                reason: signal.reason.isEmpty
                    ? "the routine signal file (.routine-signal.md) couldn't be read"
                    : signal.reason
            )
        }
    }
}
