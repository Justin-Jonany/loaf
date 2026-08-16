import Foundation
import FoolscapCore

// XCTest and swift-testing both ship only with Xcode, so `swift test` is unavailable
// on a Command Line Tools install. FoolscapCore is pure logic with no fixtures or
// mocks, so a plain executable is enough: `swift run foolscap-selftest`, non-zero
// exit on failure. One suite, runnable by every contributor and by CI.

var failures: [String] = []
var checks = 0

func expect<T: Equatable>(_ actual: T, _ expected: T, _ label: String, line: UInt = #line) {
    checks += 1
    if actual != expected {
        failures.append("line \(line)  \(label)\n    got:      \(actual)\n    expected: \(expected)")
    }
}

func expectNil<T>(_ actual: T?, _ label: String, line: UInt = #line) {
    checks += 1
    if let actual {
        failures.append("line \(line)  \(label)\n    got:      \(actual)\n    expected: nil")
    }
}

func date(_ iso: String) -> CalendarDate { CalendarDate(iso: iso)! }

// MARK: - CalendarDate

expectNil(CalendarDate(iso: "2026-02-31"), "rejects 31 February")
expectNil(CalendarDate(iso: "2026-13-01"), "rejects month 13")
expectNil(CalendarDate(iso: "not-a-date"), "rejects garbage")
expect(CalendarDate(iso: "2024-02-29")?.description, "2024-02-29", "accepts a leap day")
expect(CalendarDate(iso: "2026-08-19T14:00")?.description, "2026-08-19", "ignores a time suffix")

expect(date("2026-12-31").adding(days: 1).description, "2027-01-01", "crosses year end")
expect(date("2027-01-01").days(until: date("2026-12-31")), -1, "negative day span")

// US DST began 2026-03-08. A local-time implementation loses an hour here and can
// land on the wrong day; arithmetic pinned to UTC cannot.
expect(date("2026-03-07").adding(days: 1).description, "2026-03-08", "day before DST")
expect(date("2026-03-07").adding(days: 2).description, "2026-03-09", "day after DST")
expect(date("2026-03-07").days(until: date("2026-03-09")), 2, "span across DST")

expect(date("2026-01-31").adding(months: 1).description, "2026-02-28", "clamps to short month")
expect(date("2026-08-09") < date("2026-08-10"), true, "orders within a month")
expect(date("2025-12-31") < date("2026-01-01"), true, "orders across a year")

// MARK: - Recurrence

expect(Recurrence("week"), .weeks(1), "parses week")
expect(Recurrence("2weeks"), .weeks(2), "parses 2weeks")
expect(Recurrence("day"), .days(1), "parses day")
expect(Recurrence("3months"), .months(3), "parses 3months")
expect(Recurrence("mon,thu"), .weekdays([2, 5]), "parses weekday list")
expectNil(Recurrence("fortnight"), "rejects unknown unit")
expectNil(Recurrence(""), "rejects empty")

for raw in ["day", "2days", "week", "3weeks", "month", "mon,thu"] {
    expect(Recurrence(raw)?.rawValue, raw, "round trips \(raw)")
}

let wednesday = date("2026-08-12")
expect(Recurrence("week")!.next(after: wednesday).description, "2026-08-19", "next week")
expect(Recurrence("day")!.next(after: wednesday).description, "2026-08-13", "next day")
expect(Recurrence("mon,thu")!.next(after: wednesday).description, "2026-08-13", "Wed to Thu")
expect(Recurrence("mon,thu")!.next(after: date("2026-08-13")).description, "2026-08-17", "Thu to Mon")

// MARK: - TaskLine

expectNil(TaskLine.parse("# Heading"), "ignores headings")
expectNil(TaskLine.parse("just prose"), "ignores prose")
expectNil(TaskLine.parse(""), "ignores blank lines")
expectNil(TaskLine.parse("- a plain bullet"), "ignores non-checkbox bullets")

let padded = TaskLine.parse("- [ ] Ask about compactness   due:2026-08-12")
expect(padded?.text, "Ask about compactness", "strips alignment padding")
expect(padded?.due?.description, "2026-08-12", "reads due date")
expect(padded?.isDone, false, "unticked box")

let indented = TaskLine.parse("  - [x] Re-read §3.2 done:2026-08-11")
expect(indented?.indent, "  ", "preserves indent")
expect(indented?.isDone, true, "ticked box")
expect(indented?.text, "Re-read §3.2", "text before done field")
expect(indented?.done?.description, "2026-08-11", "reads done date")

// A colon in the prose must not be mistaken for a field.
let colons = TaskLine.parse("- [ ] email tom: ask re: the grant due:2026-08-12")
expect(colons?.text, "email tom: ask re: the grant", "keeps colons in prose")
expect(colons?.due?.description, "2026-08-12", "still finds the trailing field")

// An unparseable date is prose, not a silently dropped field.
let loose = TaskLine.parse("- [ ] thing due:tomorrow")
expect(loose?.text, "thing due:tomorrow", "keeps unparseable date as text")
expectNil(loose?.due, "does not invent a due date")

let source = "- [ ] Water the plants due:2026-08-12 every:week"
let once = TaskLine.parse(source)!.rendered()
let twice = TaskLine.parse(once)!.rendered()
expect(once, source, "render matches source")
expect(twice, once, "render is idempotent")

let (finished, none) = TaskLine.parse("- [ ] Send the sketch due:2026-08-10")!
    .completed(on: date("2026-08-12"))
expect(finished.isDone, true, "completion ticks the box")
expect(finished.done?.description, "2026-08-12", "completion stamps today")
expectNil(none, "non-recurring task has no successor")

let (closed, next) = TaskLine.parse(source)!.completed(on: date("2026-08-12"))
expect(closed.isDone, true, "recurring task is closed")
expectNil(closed.every, "closed copy drops the recurrence")
expect(next?.due?.description, "2026-08-19", "successor moves to next week")
expect(next?.isDone, false, "successor is open")
expect(next?.rendered(), "- [ ] Water the plants due:2026-08-19 every:week", "successor renders")

let today = date("2026-08-12")
func urgency(_ due: String) -> TaskLine.Urgency {
    TaskLine.parse("- [ ] x due:\(due)")!.urgency(on: today)
}
expect(urgency("2026-08-10"), .overdue, "past due is overdue")
expect(urgency("2026-08-12"), .dueToday, "same day is due today")
expect(urgency("2026-08-14"), .soon, "within two days is soon")
expect(urgency("2026-08-19"), .later, "beyond two days is later")
expect(TaskLine.parse("- [x] x due:2026-08-10")!.urgency(on: today), .none, "done tasks are never urgent")

// MARK: - Report

if failures.isEmpty {
    print("PASS — \(checks) checks")
    exit(0)
} else {
    print("FAIL — \(failures.count) of \(checks) checks\n")
    for failure in failures { print(failure, terminator: "\n\n") }
    exit(1)
}
