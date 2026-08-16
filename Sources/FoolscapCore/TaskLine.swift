import Foundation

/// One GitHub-flavoured checkbox line, plus any inline date fields on it.
///
///     - [ ] Ask about compactness   due:2026-08-12
///     - [x] Re-read §3.2            done:2026-08-11
///     - [ ] Water the plants        every:week
public struct TaskLine: Equatable, Sendable {
    public var indent: String
    public var bullet: Character
    public var isDone: Bool
    public var text: String
    public var due: CalendarDate?
    public var done: CalendarDate?
    public var every: Recurrence?

    public init(
        indent: String = "",
        bullet: Character = "-",
        isDone: Bool = false,
        text: String,
        due: CalendarDate? = nil,
        done: CalendarDate? = nil,
        every: Recurrence? = nil
    ) {
        self.indent = indent
        self.bullet = bullet
        self.isDone = isDone
        self.text = text
        self.due = due
        self.done = done
        self.every = every
    }

    private enum Field {
        case due(CalendarDate)
        case done(CalendarDate)
        case every(Recurrence)

        init?(token: String) {
            if token.hasPrefix("due:"), let date = CalendarDate(iso: String(token.dropFirst(4))) {
                self = .due(date)
            } else if token.hasPrefix("done:"), let date = CalendarDate(iso: String(token.dropFirst(5))) {
                self = .done(date)
            } else if token.hasPrefix("every:"), let rule = Recurrence(String(token.dropFirst(6))) {
                self = .every(rule)
            } else {
                return nil
            }
        }
    }

    /// Returns `nil` for any line that isn't a checkbox — headings, prose, blank lines.
    public static func parse(_ line: String) -> TaskLine? {
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
        // A bare "- [ ]" with no trailing space is still a valid empty task.
        if rest.hasPrefix(" ") { rest = rest.dropFirst() }

        var task = TaskLine(indent: indent, bullet: bullet, isDone: mark != " ", text: "")

        // Fields are consumed from the right so the text keeps its own spacing;
        // only the alignment padding before the fields is discarded.
        var body = String(rest)
        while true {
            let trimmed = Self.trimmingTrailingSpace(body)
            guard !trimmed.isEmpty else { body = trimmed; break }

            let separator = trimmed.lastIndex(where: { $0 == " " || $0 == "\t" })
            let candidate = separator.map { String(trimmed[trimmed.index(after: $0)...]) } ?? trimmed

            guard let field = Field(token: candidate) else { body = trimmed; break }
            switch field {
            case .due(let date):   task.due = date
            case .done(let date):  task.done = date
            case .every(let rule): task.every = rule
            }

            guard let separator else { body = ""; break }
            body = String(trimmed[..<separator])
        }

        task.text = body
        return task
    }

    private static func trimmingTrailingSpace(_ value: String) -> String {
        var copy = value
        while let last = copy.last, last == " " || last == "\t" { copy.removeLast() }
        return copy
    }

    /// Canonical form. Field order is fixed so repeated parse/render round-trips are stable.
    public func rendered() -> String {
        var out = "\(indent)\(bullet) [\(isDone ? "x" : " ")] \(text)"
        if let due { out += " due:\(due)" }
        if let every { out += " every:\(every.rawValue)" }
        if let done { out += " done:\(done)" }
        return out
    }

    /// Ticking the box. A recurring task also yields its next occurrence, so the
    /// caller can keep the recurrence alive instead of crossing it off for good.
    public func completed(on today: CalendarDate) -> (completed: TaskLine, next: TaskLine?) {
        var finished = self
        finished.isDone = true
        finished.done = today
        finished.every = nil

        guard let every else { return (finished, nil) }

        var upcoming = self
        upcoming.isDone = false
        upcoming.done = nil
        upcoming.due = every.next(after: due ?? today)
        return (finished, upcoming)
    }

    public enum Urgency: Equatable, Sendable {
        case none, later, soon, dueToday, overdue
    }

    public func urgency(on today: CalendarDate, soonWithinDays: Int = 2) -> Urgency {
        guard !isDone, let due else { return .none }
        let remaining = today.days(until: due)
        if remaining < 0 { return .overdue }
        if remaining == 0 { return .dueToday }
        return remaining <= soonWithinDays ? .soon : .later
    }
}
