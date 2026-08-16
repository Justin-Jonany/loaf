import Foundation

/// The value of an `every:` field on a task line.
public enum Recurrence: Equatable, Sendable {
    case days(Int)
    case weeks(Int)
    case months(Int)
    /// Specific weekdays, 1 = Sunday through 7 = Saturday.
    case weekdays(Set<Int>)

    private static let names = [
        "sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7,
    ]

    /// Parses `day`, `2days`, `week`, `2weeks`, `month`, `3months`, or `mon,thu`.
    public init?(_ raw: String) {
        let text = raw.lowercased().trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }

        if text.contains(",") || Self.names[text] != nil {
            let parsed = text.split(separator: ",").map {
                Self.names[$0.trimmingCharacters(in: .whitespaces)]
            }
            guard !parsed.contains(where: { $0 == nil }), !parsed.isEmpty else { return nil }
            self = .weekdays(Set(parsed.compactMap { $0 }))
            return
        }

        let count = Int(text.prefix(while: \.isNumber)) ?? 1
        guard count > 0 else { return nil }
        let unit = text.drop(while: \.isNumber)

        switch unit {
        case "day", "days":     self = .days(count)
        case "week", "weeks":   self = .weeks(count)
        case "month", "months": self = .months(count)
        default: return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .days(let n):   return n == 1 ? "day" : "\(n)days"
        case .weeks(let n):  return n == 1 ? "week" : "\(n)weeks"
        case .months(let n): return n == 1 ? "month" : "\(n)months"
        case .weekdays(let set):
            let byNumber = Self.names.sorted { $0.value < $1.value }
            return byNumber.filter { set.contains($0.value) }.map(\.key).joined(separator: ",")
        }
    }

    /// The first occurrence strictly after `date`.
    public func next(after date: CalendarDate) -> CalendarDate {
        switch self {
        case .days(let n):   return date.adding(days: n)
        case .weeks(let n):  return date.adding(days: 7 * n)
        case .months(let n): return date.adding(months: n)
        case .weekdays(let set):
            guard !set.isEmpty else { return date.adding(days: 1) }
            // At most seven steps reaches every weekday, so this always terminates.
            for offset in 1...7 {
                let candidate = date.adding(days: offset)
                if set.contains(candidate.weekday) { return candidate }
            }
            return date.adding(days: 7)
        }
    }
}
