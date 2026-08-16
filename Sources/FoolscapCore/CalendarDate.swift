import Foundation

/// A date with no time and no time zone.
///
/// Foolscap never stores an instant for a due date. Round-tripping a due date through
/// `Date` reintroduces a timestamp, and a later time-zone change then silently shifts
/// the day — the most common bug in todo apps. A task due the 19th is due the 19th in
/// Melbourne and in Reykjavík.
public struct CalendarDate: Hashable, Comparable, CustomStringConvertible, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Arithmetic is pinned to UTC so adding days can never cross a DST boundary and
    /// land on the wrong date. Only the question "what day is it *now*" is local.
    private static let arithmetic: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private init(unchecked year: Int, _ month: Int, _ day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Fails for dates the calendar doesn't have, such as `2026-02-31`.
    public init?(year: Int, month: Int, day: Int) {
        let components = DateComponents(year: year, month: month, day: day)
        guard let probe = Self.arithmetic.date(from: components) else { return nil }
        let actual = Self.arithmetic.dateComponents([.year, .month, .day], from: probe)
        guard actual.year == year, actual.month == month, actual.day == day else { return nil }
        self.init(unchecked: year, month, day)
    }

    /// Parses `YYYY-MM-DD`, ignoring any `THH:MM` suffix.
    public init?(iso: String) {
        let datePart = iso.prefix(while: { $0 != "T" })
        let fields = datePart.split(separator: "-", omittingEmptySubsequences: false)
        guard fields.count == 3,
              let year = Int(fields[0]),
              let month = Int(fields[1]),
              let day = Int(fields[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    public static func today(in timeZone: TimeZone = .current, now: Date = Date()) -> CalendarDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return CalendarDate(unchecked: parts.year!, parts.month!, parts.day!)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// 1 = Sunday through 7 = Saturday, matching `Calendar.component(.weekday:)`.
    public var weekday: Int {
        Self.arithmetic.component(.weekday, from: instant)
    }

    private var instant: Date {
        // Safe to force: every initialiser validates against the calendar.
        Self.arithmetic.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private static func from(_ date: Date) -> CalendarDate {
        let parts = arithmetic.dateComponents([.year, .month, .day], from: date)
        return CalendarDate(unchecked: parts.year!, parts.month!, parts.day!)
    }

    public func adding(days: Int) -> CalendarDate {
        Self.from(Self.arithmetic.date(byAdding: .day, value: days, to: instant)!)
    }

    /// Clamps to the end of a shorter month: 31 Jan plus one month is 28 or 29 Feb.
    public func adding(months: Int) -> CalendarDate {
        Self.from(Self.arithmetic.date(byAdding: .month, value: months, to: instant)!)
    }

    /// Whole days from `self` to `other`; negative when `other` is in the past.
    public func days(until other: CalendarDate) -> Int {
        Self.arithmetic.dateComponents([.day], from: instant, to: other.instant).day!
    }

    public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}
