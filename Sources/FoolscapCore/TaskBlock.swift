import Foundation

/// A task in the metadata-below format: a checkbox line, an indented metadata line
/// beneath it, and an optional further-indented free-prose note.
///
///     - [ ] Prep the client deck
///           @20aug · !high · #schoolwork · calendar
///           Focus on the pricing slide — they pushed back last time.
///     - [ ] Email the landlord
///           @today · manual
///     - [x] Read chapter 4
///           @fri · #cs101 · ✓18aug
///
/// Metadata used to live inline on the task line (see `TaskLine`); it moved to its own
/// line so the task itself reads as plain prose. `TaskBlock` reads the new format —
/// it does not read the old inline `due:`/`done:`/`every:` fields.
public struct TaskBlock: Equatable, Sendable {
    public var indent: String
    public var bullet: Character
    public var isDone: Bool
    public var text: String
    /// `nil` means the block has no `@due` — the field is required by the format, so
    /// this is a flagged/invalid block, not a silently-defaulted one. See `isValid`.
    public var due: CalendarDate?
    public var source: Source
    public var priority: Priority?
    public var type: String?
    /// The `today` placement token (DECISIONS.md 2026-09-11 — "sticky drag-to-Today"):
    /// pulls the task into the dashboard's Today section regardless of `@due`, independent
    /// of it — dragging a task into Today never touches `due`, and dragging it back out
    /// returns it to its ordinary due-date bucket. Renders as `today`; the parser also
    /// still accepts the retired `★` glyph this token replaced, so an old vault's lines
    /// keep parsing `focus == true` without needing the migration to have run.
    public var focus: Bool
    public var done: CalendarDate?
    public var every: Recurrence?
    /// The permanent archive's stamp (DECISIONS.md 2026-09-11): "when it left the list."
    /// A Foundation `Date` (an instant with time), not `CalendarDate` — a deliberate
    /// carve-out from `CalendarDate`'s own rule against storing instants (see its doc
    /// comment). `✓done` stays date-only so `tasks.md`'s existing round-trip is untouched;
    /// this field only ever appears once a block moves to an archive shard.
    public var archivedAt: Date?
    /// An `archived:` payload that was present but didn't parse as ISO-8601-with-offset
    /// (a half-written file, a future format this parser doesn't know yet, ...). Unlike an
    /// ordinary unrecognized token, this one is the archive's own audit stamp — losing it
    /// silently would be real data loss, not a harmless drop — so it's kept verbatim here
    /// and rendered back out unchanged rather than discarded. Cleared whenever a valid
    /// `archivedAt` is set.
    private var archivedRaw: String?
    public var note: String?

    public enum Source: String, Equatable, Sendable {
        case calendar, chat, manual
    }

    public enum Priority: String, Equatable, Sendable {
        case high, med, low
    }

    public init(
        indent: String = "",
        bullet: Character = "-",
        isDone: Bool = false,
        text: String,
        due: CalendarDate? = nil,
        source: Source = .manual,
        priority: Priority? = nil,
        type: String? = nil,
        focus: Bool = false,
        done: CalendarDate? = nil,
        every: Recurrence? = nil,
        note: String? = nil
    ) {
        self.indent = indent
        self.bullet = bullet
        self.isDone = isDone
        self.text = text
        self.due = due
        self.source = source
        self.priority = priority
        self.type = type
        self.focus = focus
        self.done = done
        self.every = every
        self.note = note
    }

    /// A task with no `@due` can't be bucketed (DESIGN.md → The panel): every downstream
    /// consumer must check this rather than treat a missing due date as some default day.
    public var isValid: Bool { due != nil }

    // MARK: - Parsing

    /// Parses the block starting at `lines[index]`. Returns `nil` when that line isn't a
    /// checkbox line at all — headings, prose, blank lines — same contract as
    /// `TaskLine.parse`. Otherwise always returns a block, even one missing `@due`
    /// (flagged via `isValid`), plus how many lines it consumed so a caller scanning a
    /// whole document can skip past it to the next block.
    public static func parse(
        _ lines: [String], at index: Int, today: CalendarDate = .today()
    ) -> (block: TaskBlock, consumed: Int)? {
        guard index >= 0, index < lines.count, let head = parseCheckboxLine(lines[index]) else {
            return nil
        }

        var block = head
        var consumed = 1

        if index + 1 < lines.count, isContinuation(lines[index + 1], baseIndent: head.indent.count) {
            applyMetadata(lines[index + 1], to: &block, today: today)
            consumed = 2

            if index + 2 < lines.count, isContinuation(lines[index + 2], baseIndent: head.indent.count) {
                block.note = lines[index + 2].trimmingCharacters(in: .whitespaces)
                consumed = 3
            }
        }

        return (block, consumed)
    }

    /// Convenience for a self-contained block (checkbox + metadata [+ note], `\n`-joined)
    /// with no surrounding document to scan — the common shape in tests and fixtures.
    public static func parse(_ text: String, today: CalendarDate = .today()) -> TaskBlock? {
        parse(text.components(separatedBy: "\n"), at: 0, today: today)?.block
    }

    private static func parseCheckboxLine(_ line: String) -> TaskBlock? {
        let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
        var rest = Substring(line.dropFirst(indent.count))

        guard let bullet = rest.first, bullet == "-" || bullet == "*" else { return nil }
        rest = rest.dropFirst()
        guard rest.hasPrefix(" [") else { return nil }
        rest = rest.dropFirst(2)
        guard let mark = rest.first, mark == " " || mark == "x" || mark == "X" else { return nil }
        rest = rest.dropFirst()
        guard rest.hasPrefix("]") else { return nil }
        rest = rest.dropFirst()
        if rest.hasPrefix(" ") { rest = rest.dropFirst() }

        return TaskBlock(indent: indent, bullet: bullet, isDone: mark != " ", text: trimmingTrailingSpace(String(rest)))
    }

    /// A metadata/note line: indented further than the checkbox line above it, non-blank,
    /// and not itself the start of another checkbox — a block's continuation lines stop
    /// wherever the next task begins.
    private static func isContinuation(_ line: String, baseIndent: Int) -> Bool {
        let leading = line.prefix(while: { $0 == " " || $0 == "\t" }).count
        guard leading > baseIndent else { return false }
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return parseCheckboxLine(line) == nil
    }

    /// Tokens are `·`-separated; unrecognised tokens are ignored rather than failing the
    /// whole block, so e.g. a stray word doesn't corrupt an otherwise-valid parse.
    private static func applyMetadata(_ line: String, to block: inout TaskBlock, today: CalendarDate) {
        let tokens = line
            .trimmingCharacters(in: .whitespaces)
            .split(separator: "·")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for token in tokens {
            if token.hasPrefix("@") {
                block.due = DateToken.parse(String(token.dropFirst()), today: today, preferPast: false)
            } else if token.hasPrefix("✓") {
                block.done = DateToken.parse(String(token.dropFirst()), today: today, preferPast: true)
            } else if token.hasPrefix("!"), let priority = Priority(rawValue: String(token.dropFirst()).lowercased()) {
                block.priority = priority
            } else if token.hasPrefix("#") {
                block.type = String(token.dropFirst())
            } else if token == "today" || token == "★" {
                // `today` is the modern placement token (DECISIONS.md 2026-09-11); `★` is
                // the retired glyph it replaced, still accepted so an unmigrated vault
                // keeps parsing focus == true. Matched as a standalone token here, in the
                // same slot `★` occupied — never a substring match, so a task whose free
                // text happens to contain the word "today" (that's the `note`/`text`
                // fields, not this metadata line) is never misread, and `@today` (a due
                // date) is handled entirely separately above, by the `@`-prefix branch.
                block.focus = true
            } else if token.hasPrefix("every:"), let rule = Recurrence(String(token.dropFirst(6))) {
                block.every = rule
            } else if token.hasPrefix("archived:") {
                let payload = String(token.dropFirst("archived:".count))
                if let parsed = ArchiveStamp.parse(payload) {
                    block.archivedAt = parsed
                    block.archivedRaw = nil
                } else {
                    // See `archivedRaw`'s doc comment: preserved verbatim, not dropped.
                    block.archivedRaw = payload
                }
            } else if let source = Source(rawValue: token.lowercased()) {
                block.source = source
            }
        }
    }

    private static func trimmingTrailingSpace(_ value: String) -> String {
        var copy = value
        while let last = copy.last, last == " " || last == "\t" { copy.removeLast() }
        return copy
    }

    // MARK: - Rendering

    /// Canonical form: `@due · source · !priority · #type · today · every:… · ✓done ·
    /// archived:…`, field order fixed so repeated parse/render round-trips are stable
    /// (mirrors `TaskLine.rendered()`). Dates always render as ISO — natural-language
    /// normalisation on write (`@friday` → the ISO date) is Epic F, not this parser.
    /// `archived:` is the newest field and always renders last, after `✓done`, so an
    /// already-archived-once file doesn't get its existing fields reordered. The
    /// placement token always renders as `today` (DECISIONS.md 2026-09-11), even when it
    /// was parsed from the legacy `★` — the same field slot, just the new spelling.
    public func rendered() -> String {
        var fields: [String] = []
        if let due { fields.append("@\(due)") }
        fields.append(source.rawValue)
        if let priority { fields.append("!\(priority.rawValue)") }
        if let type { fields.append("#\(type)") }
        if focus { fields.append("today") }
        if let every { fields.append("every:\(every.rawValue)") }
        if let done { fields.append("✓\(done)") }
        if let archivedAt { fields.append("archived:\(ArchiveStamp.format(archivedAt))") }
        else if let archivedRaw { fields.append("archived:\(archivedRaw)") }

        let metaIndent = indent + "      "
        var out = "\(indent)\(bullet) [\(isDone ? "x" : " ")] \(text)"
        out += "\n\(metaIndent)\(fields.joined(separator: " · "))"
        if let note { out += "\n\(metaIndent)\(note)" }
        return out
    }

    // MARK: - Checkbox write-back

    /// Applies a checkbox toggle to the block starting at `lines[index]` and returns the
    /// document with that block's lines replaced by its re-rendered form — `✓done` moves
    /// onto the metadata line (creating one if the block had none), never the task or note
    /// line. Returns `nil` when `index` isn't a checkbox line, so a caller can tell a stale
    /// click (the file changed underneath it) from a real toggle and drop it rather than
    /// write something corrupt.
    public static func toggling(
        _ lines: [String], at index: Int, checked: Bool, today: CalendarDate = .today()
    ) -> [String]? {
        guard let (block, consumed) = parse(lines, at: index, today: today) else { return nil }

        var updated = block
        updated.isDone = checked
        updated.done = checked ? today : nil

        var result = lines
        result.replaceSubrange(index..<(index + consumed), with: updated.rendered().components(separatedBy: "\n"))
        return result
    }

    /// Applies a focus-flag toggle to the block starting at `lines[index]` and returns the
    /// document with that block's lines replaced by its re-rendered form — the `today`
    /// token moves onto the metadata line, `@due` untouched either way. Returns `nil` when `index`
    /// isn't a checkbox line, so a caller can tell a stale click (the file changed underneath
    /// it) from a real toggle and drop it rather than write something corrupt.
    public static func settingFocus(
        _ lines: [String], at index: Int, focus: Bool, today: CalendarDate = .today()
    ) -> [String]? {
        guard let (block, consumed) = parse(lines, at: index, today: today) else { return nil }
        var updated = block
        updated.focus = focus
        var result = lines
        result.replaceSubrange(index..<(index + consumed), with: updated.rendered().components(separatedBy: "\n"))
        return result
    }

    // MARK: - Permanent archive write-back (DECISIONS.md 2026-09-11)

    /// Applies the archive stamp to the block at `lines[index]` and returns it rendered
    /// (for appending to the month's archive shard) alongside the source document with
    /// that block's lines removed. Mirrors `toggling`/`settingFocus`'s parse-at-line,
    /// re-render, stale-click-returns-`nil` shape exactly — the caller (`archiveTask` in
    /// `Sources/Foolscap/main.swift`) is the one that decides the write ORDER (shard
    /// first, then this removal), since that's a two-file concern this pure function
    /// doesn't touch. Deliberately leaves `isDone`/`done` exactly as found — archiving is
    /// available on any task now, not only a done one, and the archived record's whole
    /// point is to preserve whether it was done at the moment it left the list.
    public static func archiving(
        _ lines: [String], at index: Int, archivedAt: Date = Date()
    ) -> (archivedBlockText: String, remainingLines: [String])? {
        guard let (block, consumed) = parse(lines, at: index) else { return nil }
        var archived = block
        archived.archivedAt = archivedAt
        archived.archivedRaw = nil

        var remaining = lines
        remaining.removeSubrange(index..<(index + consumed))
        return (archived.rendered(), remaining)
    }

    /// The inverse of `archiving`: clears the archive stamp AND reopens the task
    /// (`isDone`/`done` cleared — DECISIONS.md 2026-09-11, "restore reopens the task").
    /// Returns the block rendered for appending to `tasks.md` alongside the archive
    /// shard's lines with that block removed.
    public static func restoring(
        _ lines: [String], at index: Int
    ) -> (restoredBlockText: String, remainingLines: [String])? {
        guard let (block, consumed) = parse(lines, at: index) else { return nil }
        var restored = block
        restored.archivedAt = nil
        restored.archivedRaw = nil
        restored.isDone = false
        restored.done = nil

        var remaining = lines
        remaining.removeSubrange(index..<(index + consumed))
        return (restored.rendered(), remaining)
    }

    // MARK: - Urgency

    public enum Urgency: Equatable, Sendable {
        case none, later, soon, dueToday, overdue
    }

    /// Mirrors `TaskLine.urgency(on:soonWithinDays:)` exactly — the dashboard (this type)
    /// and the single-note view (`TaskLine`) must agree on what counts as overdue/soon so
    /// the same due date reads the same way in both places.
    public func urgency(on today: CalendarDate, soonWithinDays: Int = Config.defaultSoonWithinDays) -> Urgency {
        guard !isDone, let due else { return .none }
        let remaining = today.days(until: due)
        if remaining < 0 { return .overdue }
        if remaining == 0 { return .dueToday }
        return remaining <= soonWithinDays ? .soon : .later
    }
}

/// ISO-8601-with-offset parsing/formatting for the `archived:` stamp — an instant, not a
/// `CalendarDate`, so it mirrors `BriefStamp`'s own `ISO8601DateFormatter` +
/// `.withInternetDateTime` pattern (`Sources/FoolscapCore/BriefStamp.swift`) rather than
/// `DateToken` below, which only ever resolves to a `CalendarDate`.
private enum ArchiveStamp {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ value: String) -> Date? { formatter.date(from: value) }
    static func format(_ date: Date) -> String { formatter.string(from: date) }
}

/// How `@due`/`✓done` tokens resolve against a reference date. Arithmetic goes through
/// `CalendarDate`, which is pinned to UTC — never `Date` — so a form spanning a DST
/// boundary can't land on the wrong day.
private enum DateToken {
    private static let weekdays: [String: Int] = [
        "sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7,
    ]
    private static let months: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
    ]

    /// Parses `today`, a weekday abbreviation, `<day><month abbrev>` (`20aug`), or ISO
    /// (`2026-08-20`). Weekday/day-month forms are relative and resolve to the nearest
    /// occurrence — forward from `today` for `@due` (`preferPast: false`), backward for
    /// `✓done` (`preferPast: true`), since a done stamp is never in the future.
    static func parse(_ token: String, today: CalendarDate, preferPast: Bool) -> CalendarDate? {
        let lower = token.lowercased()
        if lower == "today" { return today }
        if let weekday = weekdays[lower] { return nearestWeekday(weekday, today: today, preferPast: preferPast) }
        if let iso = CalendarDate(iso: token) { return iso }

        let digits = lower.prefix(while: \.isNumber)
        let monthPart = String(lower.dropFirst(digits.count))
        guard let day = Int(digits), let month = months[monthPart] else { return nil }
        return nearestDayMonth(day: day, month: month, today: today, preferPast: preferPast)
    }

    private static func nearestWeekday(_ target: Int, today: CalendarDate, preferPast: Bool) -> CalendarDate {
        let step = preferPast ? -1 : 1
        // At most seven steps reaches every weekday, so this always terminates.
        for offset in 0...6 {
            let candidate = today.adding(days: offset * step)
            if candidate.weekday == target { return candidate }
        }
        return today
    }

    /// No year is written, so the nearest occurrence wins: same year if it's already on
    /// the right side of `today`, otherwise the adjacent year.
    private static func nearestDayMonth(day: Int, month: Int, today: CalendarDate, preferPast: Bool) -> CalendarDate? {
        guard let sameYear = CalendarDate(year: today.year, month: month, day: day) else { return nil }
        if preferPast {
            if sameYear <= today { return sameYear }
            return CalendarDate(year: today.year - 1, month: month, day: day)
        } else {
            if sameYear >= today { return sameYear }
            return CalendarDate(year: today.year + 1, month: month, day: day)
        }
    }
}
