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

// MARK: - CalendarDate.effectiveToday (B5 — 6am rollover)

// Builds the `Date` a wall clock in `timeZone` would show at `year-month-day hour:minute`.
func localDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, timeZone: TimeZone) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
    return calendar.date(from: components)!
}

let newYork = TimeZone(identifier: "America/New_York")!
let losAngeles = TimeZone(identifier: "America/Los_Angeles")!

expect(
    CalendarDate.effectiveToday(in: newYork, now: localDate(2026, 8, 12, 5, 59, timeZone: newYork)).description,
    "2026-08-11",
    "05:59 local is still the previous effective day"
)
expect(
    CalendarDate.effectiveToday(in: newYork, now: localDate(2026, 8, 12, 6, 0, timeZone: newYork)).description,
    "2026-08-12",
    "06:00 local rolls the effective day forward"
)
expect(
    CalendarDate.effectiveToday(in: newYork, now: localDate(2026, 8, 12, 23, 59, timeZone: newYork)).description,
    "2026-08-12",
    "late evening stays within the day that already rolled over"
)

// US spring-forward: clocks jump from 2:00am straight to 3:00am on 2026-03-08
// (America/New_York) — that calendar day is 23 hours long.
expect(
    CalendarDate.effectiveToday(in: newYork, now: localDate(2026, 3, 8, 5, 59, timeZone: newYork)).description,
    "2026-03-07",
    "05:59 local on the spring-forward day is still the previous effective day"
)
expect(
    CalendarDate.effectiveToday(in: newYork, now: localDate(2026, 3, 8, 6, 0, timeZone: newYork)).description,
    "2026-03-08",
    "06:00 local rolls over on the spring-forward day itself"
)

// US fall-back: clocks repeat 1:00am-1:59am on 2026-11-01 (America/New_York) — that
// calendar day is 25 hours long.
expect(
    CalendarDate.effectiveToday(in: newYork, now: localDate(2026, 11, 1, 5, 59, timeZone: newYork)).description,
    "2026-10-31",
    "05:59 local on the fall-back day is still the previous effective day"
)
expect(
    CalendarDate.effectiveToday(in: newYork, now: localDate(2026, 11, 1, 6, 0, timeZone: newYork)).description,
    "2026-11-01",
    "06:00 local rolls over on the fall-back day itself"
)

// Computed in the LOCAL calendar, not off a UTC clock. Los Angeles is UTC-7 in June, so
// 00:30 local is 07:30 UTC the same UTC date — a UTC-based implementation would read the
// hour as 7 (past the rollover) instead of the true local hour 0 (before it), and would
// wrongly advance the effective day a rollover early.
expect(
    CalendarDate.effectiveToday(in: losAngeles, now: localDate(2026, 6, 15, 0, 30, timeZone: losAngeles)).description,
    "2026-06-14",
    "uses the local hour (0, before rollover), not the UTC hour (7, past it)"
)
// The reverse case: 23:59 local is already 06:59 UTC on the *next* UTC date — a
// UTC-based implementation would read the wrong (later) calendar day entirely, not just
// the wrong hour.
expect(
    CalendarDate.effectiveToday(in: losAngeles, now: localDate(2026, 6, 15, 23, 59, timeZone: losAngeles)).description,
    "2026-06-15",
    "uses the local calendar day, not the UTC day that has already turned over"
)

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

// MARK: - TaskBlock

expectNil(TaskBlock.parse("# Heading"), "ignores headings")
expectNil(TaskBlock.parse("just prose"), "ignores prose")
expectNil(TaskBlock.parse(""), "ignores blank lines")
expectNil(TaskBlock.parse("- a plain bullet"), "ignores non-checkbox bullets")

let blockToday = date("2026-08-12") // a Wednesday — see the Recurrence section above

// A checkbox line with no metadata line at all: still parses, but is flagged invalid.
let noMeta = TaskBlock.parse(["- [ ] Just a checkbox"], at: 0, today: blockToday)
expect(noMeta?.consumed, 1, "no metadata line means the block consumes only the checkbox")
expectNil(noMeta?.block.due, "no metadata line means no due date")
expect(noMeta?.block.isValid, false, "block with no metadata line is flagged invalid")

// @due is required — a metadata line present but lacking an @due token is still flagged.
let missingDue = TaskBlock.parse("- [ ] Something\n      manual", today: blockToday)
expectNil(missingDue?.due, "missing @due is not silently defaulted")
expect(missingDue?.isValid, false, "block without @due is flagged invalid")

// Absent optionals fall back to their defaults.
let bare = TaskBlock.parse("- [ ] Email the landlord\n      @today", today: blockToday)!
expect(bare.isValid, true, "block with @due is valid")
expect(bare.due?.description, "2026-08-12", "@today resolves to the reference date")
expect(bare.source, .manual, "source defaults to manual when absent")
expectNil(bare.priority, "priority is absent by default")
expectNil(bare.type, "type is absent by default")
expectNil(bare.done, "done is absent by default")
expectNil(bare.every, "every is absent by default")
expectNil(bare.note, "note is absent with no third line")

// Each @due form, resolved against the fixed reference date 2026-08-12 (Wednesday).
func dueBlock(_ token: String) -> TaskBlock {
    TaskBlock.parse("- [ ] x\n      @\(token)", today: blockToday)!
}
expect(dueBlock("today").due?.description, "2026-08-12", "@today")
expect(dueBlock("wed").due?.description, "2026-08-12", "@<today's own weekday> resolves to today, not next week")
expect(dueBlock("fri").due?.description, "2026-08-14", "@fri resolves to the coming Friday")
expect(dueBlock("20aug").due?.description, "2026-08-20", "@20aug resolves within the current year")
expect(dueBlock("5aug").due?.description, "2027-08-05", "@5aug, already past this year, rolls to next year")
expect(dueBlock("2026-09-01").due?.description, "2026-09-01", "@<ISO> is read verbatim")

// ✓done resolves the same forms, but backward (never into the future).
func doneBlock(_ token: String) -> TaskBlock {
    TaskBlock.parse("- [x] x\n      @today · ✓\(token)", today: blockToday)!
}
expect(doneBlock("12aug").done?.description, "2026-08-12", "✓<today's own day> resolves to today")
expect(doneBlock("mon").done?.description, "2026-08-10", "✓mon resolves to the most recent Monday")
expect(doneBlock("20aug").done?.description, "2025-08-20", "✓20aug, still ahead this year, rolls back a year")

// Date resolution is stable across a DST boundary (US DST began 2026-03-08).
let dstToday = date("2026-03-07")
expect(
    TaskBlock.parse("- [ ] x\n      @9mar", today: dstToday)!.due?.description,
    "2026-03-09",
    "day-month due resolves stably across the DST boundary"
)
let dstWeekdayAbbrevs = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
let dstTargetDay = dstToday.adding(days: 2)
let dstTargetAbbrev = dstWeekdayAbbrevs[dstTargetDay.weekday - 1]
expect(
    TaskBlock.parse("- [ ] x\n      @\(dstTargetAbbrev)", today: dstToday)!.due?.description,
    dstTargetDay.description,
    "weekday due resolves stably across the DST boundary"
)

// MARK: - TaskBlock.urgency (Part 2 — overdue urgency, mirrors TaskLine.urgency above)

expect(dueBlock("2026-08-10").urgency(on: blockToday), .overdue, "past due is overdue")
expect(dueBlock("today").urgency(on: blockToday), .dueToday, "same day is due today")
expect(dueBlock("2026-08-14").urgency(on: blockToday), .soon, "within two days is soon")
expect(dueBlock("2026-08-19").urgency(on: blockToday), .later, "beyond two days is later")
expect(
    TaskBlock.parse("- [x] x\n      @2026-08-10", today: blockToday)!.urgency(on: blockToday),
    .none, "done tasks are never urgent"
)

// A full block: metadata plus a further-indented note.
let fullBlock = TaskBlock.parse(
    "- [ ] Prep the client deck\n      @2026-08-20 · calendar · !high · #schoolwork\n      Focus on the pricing slide — they pushed back last time.",
    today: blockToday
)!
expect(fullBlock.text, "Prep the client deck", "reads task text as plain prose")
expect(fullBlock.due?.description, "2026-08-20", "reads due date")
expect(fullBlock.source, .calendar, "reads explicit source")
expect(fullBlock.priority, .high, "reads priority")
expect(fullBlock.type, "schoolwork", "reads type tag")
expect(fullBlock.note, "Focus on the pricing slide — they pushed back last time.", "reads the note line")

// Scanning a whole document: a block stops at the next checkbox, not past it.
let taskDoc = [
    "- [ ] Email the landlord",
    "      @today · manual",
    "- [x] Read chapter 4",
    "      @2026-08-14 · #cs101 · ✓2026-08-13",
]
let (firstBlock, firstConsumed) = TaskBlock.parse(taskDoc, at: 0, today: blockToday)!
expect(firstConsumed, 2, "first block consumes checkbox + metadata, stopping before the next checkbox")
expect(firstBlock.text, "Email the landlord", "reads first block's text")
let (secondBlock, secondConsumed) = TaskBlock.parse(taskDoc, at: 2, today: blockToday)!
expect(secondConsumed, 2, "second block consumes checkbox + metadata")
expect(secondBlock.isDone, true, "second block reads its ticked box")
expect(secondBlock.type, "cs101", "second block reads its type tag")
expect(secondBlock.done?.description, "2026-08-13", "second block reads its done stamp")

// Round trip: a block already in canonical field order renders back to its own bytes.
let canonicalBlock = "- [ ] Prep the client deck\n      @2026-08-20 · calendar · !high · #schoolwork\n      Focus on the pricing slide — they pushed back last time."
let renderedOnce = TaskBlock.parse(canonicalBlock, today: blockToday)!.rendered()
let renderedTwice = TaskBlock.parse(renderedOnce, today: blockToday)!.rendered()
expect(renderedOnce, canonicalBlock, "render matches the canonical source")
expect(renderedTwice, renderedOnce, "render is idempotent")

// Round trip covering every/done together, exercising the rest of the field order.
let recurringBlock = "- [x] Water the plants\n      @2026-08-12 · manual · every:week · ✓2026-08-05"
let recurringRendered = TaskBlock.parse(recurringBlock, today: date("2026-08-01"))!.rendered()
expect(recurringRendered, recurringBlock, "recurring + done block round trips")

// MARK: - TaskBlock (placement token — DECISIONS.md 2026-09-11: ★ renamed to `today`)

// A lone `today` token sets focus, independent of @due; the retired ★ glyph is still
// accepted so an unmigrated vault keeps parsing focus == true; absence leaves focus false.
let focusedBlock = TaskBlock.parse("- [ ] Ping the client\n      @fri · today", today: blockToday)!
expect(focusedBlock.focus, true, "a `today` token in the metadata line sets focus")
expect(focusedBlock.due?.description, "2026-08-14", "`today` doesn't disturb the rest of the metadata parse")
let legacyStarBlock = TaskBlock.parse("- [ ] Ping the client\n      @fri · manual · ★", today: blockToday)!
expect(legacyStarBlock.focus, true, "the retired ★ glyph is still parsed as focus (unmigrated vaults)")
let unfocusedBlock = TaskBlock.parse("- [ ] Ping the client\n      @fri · manual", today: blockToday)!
expect(unfocusedBlock.focus, false, "no placement token means focus defaults to false")

// rendered() places the `today` token after #type, before every:/✓done, and round-trips.
// A legacy ★ input parses to focus and re-renders as `today` — the on-disk rename applied
// on any write that re-renders the block (toggling/settingFocus/migration).
let focusedFullBlock = TaskBlock.parse(
    "- [x] Water the plants\n      @2026-08-12 · manual · #chores · ★ · every:week · ✓2026-08-05",
    today: blockToday
)!
expect(focusedFullBlock.focus, true, "a legacy ★ parses focus alongside every other field")
let focusedFullRendered = focusedFullBlock.rendered()
expect(
    focusedFullRendered, "- [x] Water the plants\n      @2026-08-12 · manual · #chores · today · every:week · ✓2026-08-05",
    "rendered() emits `today` (not ★) after #type and before every:/✓done"
)
expect(
    TaskBlock.parse(focusedFullRendered, today: blockToday)!.focus, true,
    "re-parsing a rendered focused block still reads focus == true"
)

// MARK: - TaskBlock.settingFocus (B7 — focus-flag write-back)

let focusRef = date("2026-08-20")

// Adding ★ to a block that lacked it, and removing it again, preserves every other field.
let focusDoc = [
    "- [ ] Prep the client deck",
    "      @2026-08-20 · calendar · !high · #schoolwork",
    "      Focus on the pricing slide — they pushed back last time.",
]
let starredLines = TaskBlock.settingFocus(focusDoc, at: 0, focus: true, today: focusRef)!
expect(
    starredLines[1], "      @2026-08-20 · calendar · !high · #schoolwork · today",
    "settingFocus(true) appends the `today` token after the existing metadata fields"
)
expect(starredLines[2], focusDoc[2], "the note line is untouched by starring")
let unstarredLines = TaskBlock.settingFocus(starredLines, at: 0, focus: false, today: focusRef)!
expect(
    unstarredLines[1], "      @2026-08-20 · calendar · !high · #schoolwork",
    "settingFocus(false) removes ★ again, restoring the original metadata line"
)
expect(unstarredLines[2], focusDoc[2], "the note line is still untouched by unstarring")

// A stale click — the line no longer starts a checkbox — is dropped, not written.
expectNil(
    TaskBlock.settingFocus(["# Heading"], at: 0, focus: true, today: focusRef),
    "settingFocus on a non-checkbox line returns nil"
)

// Ticking a focused task keeps its ★ — the two flags are independent.
let focusedToggleDoc = [
    "- [ ] Email the landlord",
    "      @today · manual · ★",
]
let focusedTicked = TaskBlock.toggling(focusedToggleDoc, at: 0, checked: true, today: focusRef)!
expect(
    focusedTicked[1], "      @2026-08-20 · manual · today · ✓2026-08-20",
    "ticking a focused task keeps its placement `today` token alongside the new ✓done"
)

// MARK: - TaskBlock.toggling (checkbox write-back, A4)

let toggleRef = date("2026-08-20")

// Ticking checks the box on the task line and stamps ✓done on the metadata line only.
let toggleDoc = [
    "- [ ] Email the landlord",
    "      @today · manual",
]
let tickedLines = TaskBlock.toggling(toggleDoc, at: 0, checked: true, today: toggleRef)!
expect(tickedLines[0], "- [x] Email the landlord", "ticking checks the box on the task line")
expect(tickedLines[0].contains("✓"), false, "the done stamp does not land on the task line")
expect(tickedLines[1], "      @2026-08-20 · manual · ✓2026-08-20", "✓done lands on the metadata line")

// Un-ticking flips the box back and removes the stamp again.
let untickedLines = TaskBlock.toggling(tickedLines, at: 0, checked: false, today: toggleRef)!
expect(untickedLines[0], "- [ ] Email the landlord", "un-ticking unchecks the box on the task line")
expect(untickedLines[1], "      @2026-08-20 · manual", "un-ticking removes ✓done from the metadata line")

// A note line on a third line is untouched by either direction of the toggle.
let notedDoc = [
    "- [ ] Prep the client deck",
    "      @2026-08-20 · calendar · !high · #schoolwork",
    "      Focus on the pricing slide — they pushed back last time.",
]
let notedTicked = TaskBlock.toggling(notedDoc, at: 0, checked: true, today: toggleRef)!
expect(notedTicked[0], "- [x] Prep the client deck", "ticking with a note only flips the task line's checkbox")
expect(
    notedTicked[1], "      @2026-08-20 · calendar · !high · #schoolwork · ✓2026-08-20",
    "✓done is appended after the existing metadata fields"
)
expect(notedTicked[2], notedDoc[2], "the note line is byte-for-byte unchanged")

// A checkbox with no metadata line at all still gets a well-formed one on tick — the
// stamp always has a format-correct place to land.
let bareTicked = TaskBlock.toggling(["- [ ] Just a checkbox"], at: 0, checked: true, today: toggleRef)!
expect(bareTicked.count, 2, "ticking a bare checkbox creates its metadata line")
expect(bareTicked[1], "      manual · ✓2026-08-20", "the new metadata line carries only source and the stamp")

// A stale click — the line no longer starts a checkbox — is dropped, not written.
expectNil(TaskBlock.toggling(["just prose"], at: 0, checked: true, today: toggleRef), "toggling a non-checkbox line returns nil")

// MARK: - TaskBlock (archive — `archived:` field)

// A well-formed archived: token parses as the same instant ISO8601DateFormatter would,
// and its presence doesn't disturb the rest of the parse.
let archiveStampBlock = TaskBlock.parse(
    "- [x] Water the plants\n      @2026-08-12 · manual · every:week · ✓2026-08-05 · archived:2026-08-20T14:58:00Z",
    today: blockToday
)!
expect(
    archiveStampBlock.archivedAt, ISO8601DateFormatter().date(from: "2026-08-20T14:58:00Z"),
    "archived: parses as the same instant ISO8601DateFormatter would"
)
expect(archiveStampBlock.due?.description, "2026-08-12", "archived: doesn't disturb the rest of the metadata parse")

// archived: renders as the NEW LAST field, after ✓done — and the block round-trips.
let archiveRenderRoundTrip = archiveStampBlock.rendered()
expect(
    archiveRenderRoundTrip,
    "- [x] Water the plants\n      @2026-08-12 · manual · every:week · ✓2026-08-05 · archived:2026-08-20T14:58:00Z",
    "archived: renders after every:/✓done, matching the source"
)
expect(
    TaskBlock.parse(archiveRenderRoundTrip, today: blockToday)!.archivedAt, archiveStampBlock.archivedAt,
    "re-parsing a rendered archived block still reads the same archivedAt"
)

// Absent optionals still fall back to their defaults — no archived: token means nil.
expectNil(bare.archivedAt, "no archived: token means archivedAt is nil by default")

// A malformed archived: payload (present, but not a valid ISO-8601-with-offset instant)
// must not silently vanish on a parse→render round trip — unlike an ordinary unrecognized
// token, this one is the archive's own audit stamp, so losing it would be real data loss,
// not a harmless drop (risk flagged in review).
let malformedArchiveBlock = TaskBlock.parse(
    "- [x] Water the plants\n      @2026-08-12 · manual · archived:not-a-real-instant",
    today: blockToday
)!
expectNil(malformedArchiveBlock.archivedAt, "an unparseable archived: payload does not resolve to a Date")
let malformedArchiveRendered = malformedArchiveBlock.rendered()
expect(
    malformedArchiveRendered.contains("archived:not-a-real-instant"), true,
    "a malformed archived: payload is preserved verbatim on render, not silently dropped"
)
expect(
    TaskBlock.parse(malformedArchiveRendered, today: blockToday)!.rendered(), malformedArchiveRendered,
    "the malformed archived: field round-trips stably (idempotent render)"
)

// MARK: - TaskBlock.archiving / restoring (permanent archive write-back)

let archiveInstant = ISO8601DateFormatter().date(from: "2026-08-20T14:58:00Z")!

// Archiving a single-block document removes the block entirely and stamps archivedAt,
// leaving every other field (including the note line) untouched.
let archivingDoc = [
    "- [x] Prep the client deck",
    "      @2026-08-20 · calendar · !high · #schoolwork · ✓2026-08-20",
    "      Focus on the pricing slide — they pushed back last time.",
]
let archivingResult = TaskBlock.archiving(archivingDoc, at: 0, archivedAt: archiveInstant)!
expect(archivingResult.remainingLines, [], "archiving the document's only block leaves nothing behind")
let archivedParsed = TaskBlock.parse(archivingResult.archivedBlockText, today: blockToday)!
expect(archivedParsed.text, "Prep the client deck", "the archived block keeps the task text")
expect(archivedParsed.archivedAt, archiveInstant, "the archived block carries the archivedAt stamp")
expect(archivedParsed.isDone, true, "archiving doesn't touch isDone — that's a separate ✓done concern")
expect(archivedParsed.priority, .high, "archiving leaves other metadata untouched")
expect(archivedParsed.note, "Focus on the pricing slide — they pushed back last time.", "the note line survives archiving")

// Archiving isn't gated on done anymore (DECISIONS.md 2026-09-11, widened): an open task
// archives with no ✓done, still stamped archived: — the archived record is what tells
// you it left the list still open, not silently dropped.
let openArchivingDoc = [
    "- [ ] Email the landlord",
    "      @today · manual",
]
let openArchivingResult = TaskBlock.archiving(openArchivingDoc, at: 0, archivedAt: archiveInstant)!
let openArchivedParsed = TaskBlock.parse(openArchivingResult.archivedBlockText, today: blockToday)!
expect(openArchivedParsed.isDone, false, "archiving an open task leaves isDone false")
expectNil(openArchivedParsed.done, "archiving an open task adds no ✓done stamp")
expect(openArchivedParsed.archivedAt, archiveInstant, "the archived block still carries the archivedAt stamp")

// Archiving mid-document only removes the archived block's own lines.
let archivingMultiDoc = [
    "- [ ] Email the landlord",
    "      @today · manual",
    "- [x] Prep the client deck",
    "      @2026-08-20 · calendar · ✓2026-08-20",
]
let archivingMultiResult = TaskBlock.archiving(archivingMultiDoc, at: 2, archivedAt: archiveInstant)!
expect(
    archivingMultiResult.remainingLines, ["- [ ] Email the landlord", "      @today · manual"],
    "archiving one block leaves the rest of the document untouched"
)

// A stale click — the line no longer starts a checkbox — is dropped, not written.
expectNil(TaskBlock.archiving(["# Heading"], at: 0), "archiving a non-checkbox line returns nil")

// restoring is the inverse: clears archivedAt AND reopens the task (isDone/done cleared —
// DECISIONS.md 2026-09-11, "restore reopens the task") so it doesn't land back in
// tasks.md invisible to every dashboard bucket (DashboardComposer.isEligible only shows a
// done task when done == today).
let restoringDoc = [
    "- [x] Prep the client deck",
    "      @2026-08-20 · calendar · !high · #schoolwork · ✓2026-08-20 · archived:2026-08-20T14:58:00Z",
]
let restoringResult = TaskBlock.restoring(restoringDoc, at: 0)!
expect(restoringResult.remainingLines, [], "restoring the shard's only block leaves nothing behind")
let restoredParsed = TaskBlock.parse(restoringResult.restoredBlockText, today: blockToday)!
expect(restoredParsed.isDone, false, "restoring reopens the task — isDone is cleared")
expectNil(restoredParsed.done, "restoring clears the ✓done stamp")
expectNil(restoredParsed.archivedAt, "restoring clears the archived: stamp")
expect(restoredParsed.due?.description, "2026-08-20", "restoring leaves @due untouched")
expect(restoredParsed.priority, .high, "restoring leaves other metadata (priority) untouched")

// A stale click on the archive shard — the line no longer starts a checkbox — is dropped.
expectNil(TaskBlock.restoring(["# Heading"], at: 0), "restoring a non-checkbox line returns nil")

// MARK: - Archive (archive shard pathing)

let archiveTestVaultDir = tempVaultDir()
let archiveTestVault = Vault(root: archiveTestVaultDir)
let archiveTestUTC = TimeZone(identifier: "UTC")!

let shardInstant = localDate(2026, 9, 5, 12, 0, timeZone: archiveTestUTC)
let shardURL = Archive.archiveShardURL(for: shardInstant, vault: archiveTestVault, timeZone: archiveTestUTC)
expect(
    shardURL.path, archiveTestVaultDir.appendingPathComponent("archive/2026-09.md").path,
    "archiveShardURL builds <vault>/archive/YYYY-MM.md for the instant's month"
)

// A single-digit month is zero-padded, not left as a stray "2026-9.md".
let januaryInstant = localDate(2026, 1, 3, 9, 0, timeZone: archiveTestUTC)
let januaryShard = Archive.archiveShardURL(for: januaryInstant, vault: archiveTestVault, timeZone: archiveTestUTC)
expect(januaryShard.lastPathComponent, "2026-01.md", "archiveShardURL zero-pads a single-digit month")

// MARK: - Vault

func tempVaultDir() -> URL {
    // Resolved once up front: /tmp (and macOS's real temp dir) are themselves symlinks,
    // so an unresolved URL here would never string-compare equal to the paths FileManager
    // hands back from directory enumeration later.
    FileManager.default.temporaryDirectory
        .appendingPathComponent("foolscap-selftest-\(UUID().uuidString)")
        .resolvingSymlinksInPath()
}

do {
    let dir = tempVaultDir()
    let vault = Vault(root: dir)

    try vault.bootstrapIfEmpty()
    let claudePath = dir.appendingPathComponent("CLAUDE.md")
    expect(FileManager.default.fileExists(atPath: claudePath.path), true, "bootstrap creates CLAUDE.md")
    let seeded = (try? String(contentsOf: claudePath, encoding: .utf8)) ?? ""
    expect(seeded.contains("Foolscap vault"), true, "bootstrapped CLAUDE.md carries the vault contract")

    // A second bootstrap must not clobber a CLAUDE.md the user has since edited.
    try vault.writeAtomically("edited by user", to: claudePath)
    try vault.bootstrapIfEmpty()
    let after = (try? String(contentsOf: claudePath, encoding: .utf8)) ?? ""
    expect(after, "edited by user", "bootstrap does not overwrite an existing CLAUDE.md")

    try? FileManager.default.removeItem(at: dir)
} catch {
    failures.append("Vault bootstrap threw: \(error)")
}

do {
    let dir = tempVaultDir()
    let vault = Vault(root: dir)

    try vault.writeAtomically("# Todo\n", to: dir.appendingPathComponent("todo.md"))
    try vault.writeAtomically("# Hidden\n", to: dir.appendingPathComponent(".hidden.md"))
    try vault.writeAtomically("# Daily\n", to: dir.appendingPathComponent("daily/2026-08-15.md"))
    try vault.writeAtomically("not a note\n", to: dir.appendingPathComponent("attachments/note.md"))
    try Data().write(to: dir.appendingPathComponent("attachments/photo.png"))

    // Compared by suffix, not by stripping `dir.path` as a prefix: macOS's real temp
    // directory sits behind a `/private` symlink that directory enumeration resolves
    // but a freshly-built (not-yet-existing-on-disk) URL does not.
    let paths = vault.notePaths().map(\.path)
    expect(paths.count, 2, "notePaths returns exactly the two real notes")
    expect(paths.contains { $0.hasSuffix("/todo.md") }, true, "notePaths includes todo.md")
    expect(paths.contains { $0.hasSuffix("/daily/2026-08-15.md") }, true, "notePaths includes daily/2026-08-15.md")
    expect(paths.contains { $0.hasSuffix("/.hidden.md") }, false, "notePaths ignores dotfiles")
    expect(paths.contains { $0.contains("/attachments/") }, false, "notePaths ignores attachments/")

    try? FileManager.default.removeItem(at: dir)
} catch {
    failures.append("Vault notePaths threw: \(error)")
}

do {
    let dir = tempVaultDir()
    let vault = Vault(root: dir)
    let path = dir.appendingPathComponent("todo.md")

    try vault.writeAtomically("- [ ] one\n", to: path)
    expect(try vault.read(path), "- [ ] one\n", "writeAtomically round-trips content")
    expect(vault.wasSelfWrite(path: path.path), true, "registry flags the just-written path")
    expect(vault.wasSelfWrite(path: path.path), false, "registry entry is consumed after one check")
    expect(
        vault.wasSelfWrite(path: dir.appendingPathComponent("nonexistent.md").path),
        false,
        "registry doesn't flag a path we never wrote"
    )

    try? FileManager.default.removeItem(at: dir)
} catch {
    failures.append("Vault writeAtomically threw: \(error)")
}

// A checkbox toggle's write is recognised as our own (the suppression registry
// `VaultWatcher` consults via `wasSelfWrite`), so it doesn't retrigger a reload — but a
// genuine external edit landing right after must still be seen, or a real concurrent
// edit would get silently swallowed instead of triggering the reload that shows it.
do {
    let dir = tempVaultDir()
    let vault = Vault(root: dir)
    let path = dir.appendingPathComponent("tasks.md")

    let original = "- [ ] Email the landlord\n      @today · manual"
    try vault.writeAtomically(original, to: path)

    let toggled = TaskBlock.toggling(
        original.components(separatedBy: "\n"), at: 0, checked: true, today: date("2026-08-20")
    )!
    try vault.writeAtomically(toggled.joined(separator: "\n"), to: path)
    expect(vault.wasSelfWrite(path: path.path), true, "the toggle's own write is recognised as ours")

    // Written directly (bypassing Vault), as a concurrent editor would — not through
    // `writeAtomically`, so it never lands in the self-write registry.
    try "- [ ] a concurrent external edit\n      @today · manual".write(to: path, atomically: true, encoding: .utf8)
    expect(
        vault.wasSelfWrite(path: path.path), false,
        "a genuine external edit after the toggle is not mistaken for our own echo"
    )

    try? FileManager.default.removeItem(at: dir)
} catch {
    failures.append("Toggle self-write suppression threw: \(error)")
}

// MARK: - Config

func tempConfigPath() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("foolscap-selftest-config-\(UUID().uuidString).toml")
}

let missingConfig = Config.load(from: tempConfigPath())
expect(missingConfig.vault, nil, "absent config file leaves vault nil")
expect(missingConfig.theme, Config.defaultTheme, "absent config file defaults theme")
expect(missingConfig.startMode, Config.defaultStartMode, "absent config file defaults start_mode")
expect(missingConfig.soonWithinDays, Config.defaultSoonWithinDays, "absent config file defaults soon_within_days")
expect(missingConfig.weekStarts, Config.defaultWeekStarts, "absent config file defaults week_starts")

do {
    let path = tempConfigPath()
    try "theme = \"console\"\n\n[dates]\nsoon_within_days = 5\n".write(to: path, atomically: true, encoding: .utf8)
    let partial = Config.load(from: path)
    expect(partial.theme, "console", "partial config overrides theme")
    expect(partial.soonWithinDays, 5, "partial config overrides soon_within_days")
    expect(partial.vault, nil, "partial config leaves unset vault at default")
    expect(partial.startMode, Config.defaultStartMode, "partial config leaves unset start_mode at default")
    expect(partial.weekStarts, Config.defaultWeekStarts, "partial config leaves unset week_starts at default")
    try? FileManager.default.removeItem(at: path)
} catch {
    failures.append("Config partial-load threw: \(error)")
}

let configWithVault = Config(vault: "/tmp/foolscap-selftest-config-vault")
let defaultVaultPath = ("~/Notes" as NSString).expandingTildeInPath

expect(
    Vault.resolveRoot(config: configWithVault, environment: [:]).path,
    "/tmp/foolscap-selftest-config-vault",
    "config vault path is used when $FOOLSCAP_VAULT is unset"
)
expect(
    Vault.resolveRoot(config: configWithVault, environment: ["FOOLSCAP_VAULT": "/tmp/foolscap-selftest-env-vault"]).path,
    "/tmp/foolscap-selftest-env-vault",
    "$FOOLSCAP_VAULT overrides the config vault path"
)
expect(
    Vault.resolveRoot(config: configWithVault, environment: ["FOOLSCAP_VAULT": ""]).path,
    "/tmp/foolscap-selftest-config-vault",
    "an empty $FOOLSCAP_VAULT does not override"
)
expect(
    Vault.resolveRoot(config: Config(), environment: [:]).path,
    defaultVaultPath,
    "falls back to ~/Notes when neither env nor config set a vault"
)

// MARK: - MarkdownRenderer

let overdueHTML = MarkdownRenderer.renderHTML(
    from: "- [ ] Ask about compactness due:2026-08-10\n",
    today: date("2026-08-12")
)
expect(overdueHTML.contains("<input type=\"checkbox\""), true, "renders a real checkbox for a task line")
expect(overdueHTML.contains("class=\"due due-over\""), true, "overdue due date carries the due-over class")
expect(overdueHTML.contains("Ask about compactness"), true, "task text survives into the label")

let doneHTML = MarkdownRenderer.renderHTML(from: "- [x] done thing\n")
expect(doneHTML.contains("checkbox\" checked"), true, "checked box renders the checked attribute")
expect(doneHTML.contains("class=\"task done\""), true, "done task carries the done class")

expect(overdueHTML.contains("data-line=\"1\""), true, "task div carries its 1-based source line")
expect(overdueHTML.contains("disabled"), false, "checkbox is not disabled — clicks can write back")

let allTasksHTML = MarkdownRenderer.renderHTML(from: "- [ ] one\n- [x] two\n")
expect(allTasksHTML.contains("<ul class=\"tasks\">"), true, "an all-task list wrapper gets class=\"tasks\"")

let mixedListHTML = MarkdownRenderer.renderHTML(from: "- [ ] one\n- just a bullet\n")
expect(mixedListHTML.contains("class=\"tasks\""), false, "a mixed task/non-task list keeps normal indent")

let plainListHTML = MarkdownRenderer.renderHTML(from: "- one\n- two\n")
expect(plainListHTML.contains("class=\"tasks\""), false, "a non-task list does not get class=\"tasks\"")

let soonHTML = MarkdownRenderer.renderHTML(from: "- [ ] soon due:2026-08-13\n", today: date("2026-08-12"))
expect(soonHTML.contains("class=\"due due-soon\""), true, "soon due date carries the due-soon class")

let laterHTML = MarkdownRenderer.renderHTML(from: "- [ ] later due:2026-08-30\n", today: date("2026-08-12"))
expect(laterHTML.contains("due-soon"), false, "a distant due date carries no urgency class")
expect(laterHTML.contains("due-over"), false, "a distant due date carries no urgency class")

expect(MarkdownRenderer.renderHTML(from: "# Title\n"), "<h1>Title</h1>\n", "heading renders")
expect(MarkdownRenderer.renderHTML(from: "Just some prose.\n"), "<p>Just some prose.</p>\n", "plain paragraph renders")

let escapedHTML = MarkdownRenderer.renderHTML(from: "5 < 6 & 7 > 4\n")
expect(escapedHTML.contains("&lt;"), true, "escapes < in text")
expect(escapedHTML.contains("&amp;"), true, "escapes & in text")

// MARK: - Dashboard (B1 — bucketing)

let dashToday = date("2026-08-12") // a Wednesday

// due-today → Today, not This-week (the dedup: each task lands in exactly one bucket).
let dueTodayTasks = "- [ ] Email the landlord\n      @today · manual"
let dueTodayDash = DashboardComposer.compose(
    brief: "", tasksMarkdown: dueTodayTasks, longtermMarkdown: "", today: dashToday
)
expect(dueTodayDash.today.count, 1, "due-today task lands in Today")
expect(dueTodayDash.today.first?.block.text, "Email the landlord", "Today carries the right task")
expect(dueTodayDash.thisWeek.count, 0, "due-today task does not also appear in This week")

// overdue → Today.
let overdueTasks = "- [ ] Prep the client deck\n      @2026-08-10 · manual"
let overdueDash = DashboardComposer.compose(
    brief: "", tasksMarkdown: overdueTasks, longtermMarkdown: "", today: dashToday
)
expect(overdueDash.today.count, 1, "overdue task lands in Today")
expect(overdueDash.thisWeek.count, 0, "overdue task does not also appear in This week")

// due in 3 days → This week.
let dueSoonTasks = "- [ ] Return library books\n      @2026-08-15 · manual"
let dueSoonDash = DashboardComposer.compose(
    brief: "", tasksMarkdown: dueSoonTasks, longtermMarkdown: "", today: dashToday
)
expect(dueSoonDash.thisWeek.count, 1, "task due in 3 days lands in This week")
expect(dueSoonDash.today.count, 0, "task due in 3 days is not also in Today")

// A checked/done task completed on a *different* day than `today` doesn't show — only
// a completion matching `today` lingers (ROADMAP B6; see the dedicated section below).
let doneTasks = "- [x] Already finished\n      @2026-08-11 · manual · ✓2026-08-11"
let doneDash = DashboardComposer.compose(
    brief: "", tasksMarkdown: doneTasks, longtermMarkdown: "", today: dashToday
)
expect(doneDash.today.count, 0, "a done task doesn't land in Today")
expect(doneDash.thisWeek.count, 0, "a done task doesn't land in This week")

// A task with no @due can't be bucketed at all — flagged invalid, not defaulted.
let noDueTasks = "- [ ] No due date\n      manual"
let noDueDash = DashboardComposer.compose(
    brief: "", tasksMarkdown: noDueTasks, longtermMarkdown: "", today: dashToday
)
expect(noDueDash.today.count, 0, "a task with no @due is not placed in Today")
expect(noDueDash.thisWeek.count, 0, "a task with no @due is not placed in This week")

// longterm.md's unchecked tasks land in Long-term regardless of how far out @due is.
let longtermTasks = "- [ ] Ship v2\n      @2027-01-01 · manual"
let longtermDash = DashboardComposer.compose(
    brief: "", tasksMarkdown: "", longtermMarkdown: longtermTasks, today: dashToday
)
expect(longtermDash.longTerm.count, 1, "longterm.md's task lands in Long-term")
expect(longtermDash.longTerm.first?.sourceFile, "longterm.md", "Long-term task carries its source file")

// Brief is passed through verbatim as prose, not touched by bucketing.
let briefDash = DashboardComposer.compose(
    brief: "Shipped the deck. Slipping: the report.", tasksMarkdown: "", longtermMarkdown: "", today: dashToday
)
expect(briefDash.brief, "Shipped the deck. Slipping: the report.", "Brief carries the prose verbatim")

// Each DashboardTask carries the 1-based source line it came from, for a later
// write-back path to find its way back to the exact line.
let linedTasks = [
    "- [ ] first",
    "      @today · manual",
    "- [ ] second",
    "      @2026-08-15 · manual",
].joined(separator: "\n")
let linedDash = DashboardComposer.compose(
    brief: "", tasksMarkdown: linedTasks, longtermMarkdown: "", today: dashToday
)
expect(linedDash.today.first?.line, 1, "first task's checkbox line is line 1")
expect(linedDash.thisWeek.first?.line, 3, "second task's checkbox line is line 3")

// A stray file like notes.md is never read — DashboardComposer(vault:) only ever asks
// for brief.md/tasks.md/longterm.md by name.
do {
    let dir = tempVaultDir()
    let vault = Vault(root: dir)
    try vault.writeAtomically("- [ ] from tasks.md\n      @today · manual\n", to: dir.appendingPathComponent("tasks.md"))
    try vault.writeAtomically("- [ ] from a stray file\n      @today · manual\n", to: dir.appendingPathComponent("notes.md"))

    let vaultDash = DashboardComposer.compose(vault: vault, today: dashToday)
    expect(vaultDash.today.count, 1, "only tasks.md's task is read")
    expect(vaultDash.today.first?.block.text, "from tasks.md", "the stray notes.md task is ignored")

    try? FileManager.default.removeItem(at: dir)
} catch {
    failures.append("Dashboard vault compose threw: \(error)")
}

// MARK: - Dashboard (B7 — Curated Today: ★ pulls a task into Today)

// A task due 3 days out normally lands in This week (see the B1 case above); starring it
// pulls it into Today instead, and it's claimed by exactly one bucket, not both.
let starredSoonTasks = "- [ ] Return library books\n      @2026-08-15 · manual · ★"
let starredSoonDash = DashboardComposer.compose(
    brief: "", tasksMarkdown: starredSoonTasks, longtermMarkdown: "", today: dashToday
)
expect(starredSoonDash.today.count, 1, "a starred task due in 3 days lands in Today")
expect(starredSoonDash.thisWeek.count, 0, "a starred task is not also claimed by This week")

// The same task, unstarred, reverts to its ordinary due-date bucket.
let unstarredSoonDash = DashboardComposer.compose(
    brief: "", tasksMarkdown: dueSoonTasks, longtermMarkdown: "", today: dashToday
)
expect(unstarredSoonDash.thisWeek.count, 1, "without ★ the same task lands in This week, not Today")
expect(unstarredSoonDash.today.count, 0, "without ★ the same task doesn't land in Today")

// A starred longterm.md item is pulled into Today too, not left in Long-term.
let starredLongtermTasks = "- [ ] Ship v2\n      @2027-01-01 · manual · ★"
let starredLongtermDash = DashboardComposer.compose(
    brief: "", tasksMarkdown: "", longtermMarkdown: starredLongtermTasks, today: dashToday
)
expect(starredLongtermDash.today.count, 1, "a starred longterm.md item lands in Today")
expect(starredLongtermDash.longTerm.count, 0, "a starred longterm.md item is not also claimed by Long-term")
expect(
    starredLongtermDash.today.first?.sourceFile, "longterm.md",
    "the pulled-forward item still carries its longterm.md source file"
)

// MARK: - ConflictGuard (X1 — write-conflict guard)

// The pure decision rule, all four combinations of the two facts it takes.
expect(
    ConflictDecision.decide(diskChangedSinceRead: false, bufferDirty: false), .writeThrough,
    "clean disk + clean buffer writes through"
)
expect(
    ConflictDecision.decide(diskChangedSinceRead: false, bufferDirty: true), .writeThrough,
    "clean disk + dirty buffer still writes through — nothing on disk to conflict with"
)
expect(
    ConflictDecision.decide(diskChangedSinceRead: true, bufferDirty: false), .reloadClean,
    "disk-changed + clean-buffer is a plain reload"
)
expect(
    ConflictDecision.decide(diskChangedSinceRead: true, bufferDirty: true), .conflictKeepDiskSaveCopy,
    "disk-changed + dirty-buffer decides to conflict rather than clobber"
)

// Conflict-copy naming: `<name>.conflict-<UTC timestamp>.<ext>`, next to the original.
var conflictStampComponents = DateComponents()
conflictStampComponents.year = 2026
conflictStampComponents.month = 8
conflictStampComponents.day = 20
conflictStampComponents.hour = 7
conflictStampComponents.minute = 58
conflictStampComponents.second = 3
var utcCalendar = Calendar(identifier: .gregorian)
utcCalendar.timeZone = TimeZone(identifier: "UTC")!
let conflictTimestamp = utcCalendar.date(from: conflictStampComponents)!
let conflictURL = ConflictCopy.url(for: URL(fileURLWithPath: "/vault/tasks.md"), timestamp: conflictTimestamp)
expect(
    conflictURL.lastPathComponent, "tasks.conflict-20260820-075803.md",
    "conflict copy filename embeds the original name, a sortable UTC timestamp, and the extension"
)
expect(
    conflictURL.deletingLastPathComponent().path, "/vault",
    "conflict copy sits in the same directory as the original, not a subfolder"
)

// Self-write suppression: our own write since the read snapshot is not an external change.
do {
    let dir = tempVaultDir()
    let vault = Vault(root: dir)
    let path = dir.appendingPathComponent("tasks.md")

    try vault.writeAtomically("- [ ] one\n      @today · manual", to: path)
    let readSnapshot = FileSnapshot.current(at: path)!

    // A second write we make ourselves (e.g. another toggle) before the check — still
    // recorded in the self-write registry.
    try vault.writeAtomically("- [ ] one\n      @today · manual · ✓2026-08-20", to: path)
    expect(
        ConflictGuard.hasExternalChange(at: path, since: readSnapshot, vault: vault), false,
        "a self-write is not treated as an external change"
    )

    try? FileManager.default.removeItem(at: dir)
} catch {
    failures.append("ConflictGuard self-write threw: \(error)")
}

// A genuine external edit (bypassing Vault, so it never lands in the self-write registry)
// since the read snapshot is detected.
do {
    let dir = tempVaultDir()
    let vault = Vault(root: dir)
    let path = dir.appendingPathComponent("tasks.md")

    try vault.writeAtomically("- [ ] one\n      @today · manual", to: path)
    let readSnapshot = FileSnapshot.current(at: path)!

    try "- [ ] a concurrent external edit\n      @today · manual".write(to: path, atomically: true, encoding: .utf8)
    expect(
        ConflictGuard.hasExternalChange(at: path, since: readSnapshot, vault: vault), true,
        "a genuine external edit since the read snapshot is detected"
    )

    try? FileManager.default.removeItem(at: dir)
} catch {
    failures.append("ConflictGuard external-change threw: \(error)")
}

// Real temp-dir round trip: disk-changed + dirty-buffer keeps the on-disk version and
// writes an actual `.conflict-<timestamp>.md` sidecar carrying the app's unsaved change.
do {
    let dir = tempVaultDir()
    let vault = Vault(root: dir)
    let path = dir.appendingPathComponent("tasks.md")

    let original = "- [ ] Email the landlord\n      @today · manual"
    try vault.writeAtomically(original, to: path)
    let readSnapshot = FileSnapshot.current(at: path)!

    // The morning run rewrites the file concurrently...
    let externalRewrite = original + "\n- [ ] Added by the morning run\n      @2026-08-21 · calendar"
    try externalRewrite.write(to: path, atomically: true, encoding: .utf8)
    // ...while the app has an in-flight toggle based on the version it originally read.
    let dirtyBuffer = TaskBlock.toggling(
        original.components(separatedBy: "\n"), at: 0, checked: true, today: date("2026-08-20")
    )!.joined(separator: "\n")

    let diskChanged = ConflictGuard.hasExternalChange(at: path, since: readSnapshot, vault: vault)
    expect(diskChanged, true, "the concurrent external rewrite is detected")

    let decision = ConflictDecision.decide(diskChangedSinceRead: diskChanged, bufferDirty: true)
    expect(decision, .conflictKeepDiskSaveCopy, "disk-changed + dirty-buffer decides to conflict")

    if decision == .conflictKeepDiskSaveCopy {
        try vault.writeAtomically(dirtyBuffer, to: ConflictCopy.url(for: path, timestamp: Date()))
    }

    expect(try vault.read(path), externalRewrite, "the on-disk version is kept, never clobbered")
    let conflictFiles = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        .filter { $0.hasPrefix("tasks.conflict-") && $0.hasSuffix(".md") }
    expect(conflictFiles.count, 1, "exactly one .conflict-<timestamp>.md sidecar is written")
    if let name = conflictFiles.first {
        expect(
            try vault.read(dir.appendingPathComponent(name)), dirtyBuffer,
            "the app's unsaved change is preserved in the conflict copy"
        )
    }

    try? FileManager.default.removeItem(at: dir)
} catch {
    failures.append("Conflict round-trip threw: \(error)")
}

// Real temp-dir round trip: disk-changed + clean-buffer is a plain reload — no conflict
// file, and the external rewrite is left exactly as-is.
do {
    let dir = tempVaultDir()
    let vault = Vault(root: dir)
    let path = dir.appendingPathComponent("tasks.md")

    let original = "- [ ] Email the landlord\n      @today · manual"
    try vault.writeAtomically(original, to: path)
    let readSnapshot = FileSnapshot.current(at: path)!

    let externalRewrite = original + "\n- [ ] Added by the morning run\n      @2026-08-21 · calendar"
    try externalRewrite.write(to: path, atomically: true, encoding: .utf8)

    let diskChanged = ConflictGuard.hasExternalChange(at: path, since: readSnapshot, vault: vault)
    let decision = ConflictDecision.decide(diskChangedSinceRead: diskChanged, bufferDirty: false)
    expect(decision, .reloadClean, "disk-changed + clean-buffer decides to reload, not conflict")

    let entries = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    expect(entries.contains { $0.contains(".conflict-") }, false, "a clean reload writes no conflict file")
    expect(try vault.read(path), externalRewrite, "disk keeps the external rewrite untouched")

    try? FileManager.default.removeItem(at: dir)
} catch {
    failures.append("Conflict clean-reload threw: \(error)")
}

// MARK: - DashboardTaskRenderer (B4 — tidy task rendering)

// Display ≠ storage (DESIGN.md → Tasks): the rendered fragment must carry none of the
// raw @/#/! metadata tokens, however it dresses that data up as chips/tags/dots/icons.
// `blockToday` (2026-08-12) drives the due chip's human phrasing (C1) here too — the raw
// ISO date still lives in `title` so hovering shows the exact date.
let tidyFull = DashboardTaskRenderer.render(fullBlock, today: blockToday)
expect(tidyFull.contains("@"), false, "no raw @ in a fully-tagged task's render")
expect(tidyFull.contains("#"), false, "no raw # in a fully-tagged task's render")
expect(tidyFull.contains("!"), false, "no raw ! in a fully-tagged task's render")
expect(
    tidyFull,
    "<span class=\"label\">Prep the client deck</span><span class=\"due\" title=\"2026-08-20\">Aug 20</span>"
        + "<span class=\"type\">schoolwork</span><span class=\"priority-dot high\" title=\"high priority\"></span>"
        + "<span class=\"source-icon calendar\" title=\"calendar\">📅</span>",
    "a fully-tagged task renders as sentence + due chip (human text, ISO title) + type tag + priority dot + source icon"
)

// A task with only @due (no priority/type/note) renders cleanly: the sentence, its due
// chip, and the always-present source icon — no stray markup for the absent fields.
let tidyBare = DashboardTaskRenderer.render(bare, today: blockToday)
expect(tidyBare.contains("@"), false, "no raw @ in a due-only task's render")
expect(tidyBare.contains("#"), false, "no raw # in a due-only task's render")
expect(tidyBare.contains("!"), false, "no raw ! in a due-only task's render")
expect(tidyBare.contains("type"), false, "no type tag when #type is absent")
expect(tidyBare.contains("priority-dot"), false, "no priority dot when !priority is absent")
expect(
    tidyBare,
    "<span class=\"label\">Email the landlord</span><span class=\"due due-soon\" title=\"2026-08-12\">Today</span>"
        + "<span class=\"source-icon manual\" title=\"manual\">✎</span>",
    "a due-only task renders cleanly with no stray markup for the absent fields — its due date"
        + " (today) carries the due-soon class"
)

// MARK: - DashboardTaskRenderer urgency classes (Part 2 — overdue urgency wired into the chip)

func urgencyBlock(_ due: String) -> TaskBlock {
    TaskBlock.parse("- [ ] x\n      @\(due)", today: blockToday)!
}

let overdueDashHTML = DashboardTaskRenderer.render(urgencyBlock("2026-08-10"), today: blockToday)
expect(overdueDashHTML.contains("class=\"due due-over\""), true, "overdue task's due chip carries due-over")

let dueTodayDashHTML = DashboardTaskRenderer.render(urgencyBlock("2026-08-12"), today: blockToday)
expect(dueTodayDashHTML.contains("class=\"due due-soon\""), true, "due-today task's due chip carries due-soon, not due-over")

let soonDashHTML = DashboardTaskRenderer.render(urgencyBlock("2026-08-14"), today: blockToday)
expect(soonDashHTML.contains("class=\"due due-soon\""), true, "soon task's due chip carries due-soon")

let laterDashHTML = DashboardTaskRenderer.render(urgencyBlock("2026-08-19"), today: blockToday)
expect(laterDashHTML.contains("due-soon"), false, "a distant due date carries no urgency class")
expect(laterDashHTML.contains("due-over"), false, "a distant due date carries no urgency class")

let doneOverdueDashHTML = DashboardTaskRenderer.render(
    TaskBlock.parse("- [x] x\n      @2026-08-10", today: blockToday)!, today: blockToday
)
expect(doneOverdueDashHTML.contains("due-soon"), false, "a done task's past due date carries no urgency class")
expect(doneOverdueDashHTML.contains("due-over"), false, "a done task's past due date carries no urgency class")

// soonWithinDays threading: a task 4 days out only reads as soon once the caller widens
// the window — proves the parameter (not just the default) is actually read.
let thresholdBlock = urgencyBlock("2026-08-16")
expect(
    DashboardTaskRenderer.render(thresholdBlock, today: blockToday).contains("due-soon"),
    false, "4 days out is not soon under the default 2-day window"
)
expect(
    DashboardTaskRenderer.render(thresholdBlock, today: blockToday, soonWithinDays: 5).contains("class=\"due due-soon\""),
    true, "4 days out is soon once soonWithinDays widens to 5"
)

// MARK: - DashboardTaskRenderer.renderFocusToggle (B7 — focus toggle)

let focusToggleOn = DashboardTaskRenderer.renderFocusToggle(focusedBlock)
expect(focusToggleOn.contains("aria-pressed=\"true\""), true, "a focused block's toggle reports aria-pressed=\"true\"")
let focusToggleOff = DashboardTaskRenderer.renderFocusToggle(bare)
expect(focusToggleOff.contains("aria-pressed=\"false\""), true, "an unfocused block's toggle reports aria-pressed=\"false\"")

// The ★ glyph is retired from the UI entirely (DECISIONS.md 2026-09-11): neither the tidy
// chips nor the placement handle render a star — the handle is a neutral drag grip, and a
// task's presence in Today is the only placement indicator. It stays the drag source.
expect(DashboardTaskRenderer.render(focusedBlock, today: blockToday).contains("★"), false, "the tidy label/chip render carries no raw ★")
expect(focusToggleOn.contains("★"), false, "the placement handle no longer renders the retired ★ glyph")
expect(focusToggleOff.contains("★"), false, "an unfocused placement handle renders no ★ either")
expect(focusToggleOn.contains("draggable=\"true\""), true, "the placement handle is the drag source for drag-to-Today")

// MARK: - TokenMigration (★ → `today` one-time on-disk rename — DECISIONS.md 2026-09-11)

// A document that still carries ★ is re-rendered with the `today` token; the file is
// returned whole so the caller can write it back atomically.
let dirtyVaultMd = "- [ ] Return books\n      @2026-08-15 · manual · ★\n"
let migratedVaultMd = TokenMigration.migrate(dirtyVaultMd, today: blockToday)
expect(migratedVaultMd != nil, true, "migrate rewrites a document that still contains ★")
expect(migratedVaultMd?.contains("★") ?? true, false, "no ★ remains after migration")
expect(migratedVaultMd?.contains("· today") ?? false, true, "the ★ became the `today` token")
// Idempotent: re-running on the migrated output finds nothing to change (nil).
expectNil(TokenMigration.migrate(migratedVaultMd ?? "", today: blockToday), "migrating already-clean output is a no-op (nil)")
// A document with no ★ is never rewritten — a clean vault is left byte-for-byte.
expectNil(TokenMigration.migrate("- [ ] Plain task\n      @2026-08-15 · manual\n", today: blockToday), "a document with no ★ returns nil")

// MARK: - DashboardTaskRenderer.renderArchiveButton (archive — clear/archive action)

// A one-shot action, not a toggle like renderFocusToggle above — no aria-pressed, just a
// labelled button naming the action and the task. Rendered on every row now (done or
// not — DECISIONS.md 2026-09-11, widened), so its visible content is a muted glyph, not
// the word "Archive"; the accessible name still spells the action out.
let archiveButtonHTML = DashboardTaskRenderer.renderArchiveButton(fullBlock)
expect(archiveButtonHTML.contains("aria-pressed"), false, "the archive button is an action, not a toggle — no aria-pressed")
expect(
    archiveButtonHTML.contains("aria-label=\"Archive: Prep the client deck\""), true,
    "the archive button's accessible name names the action and the task"
)
expect(archiveButtonHTML.contains("class=\"archive-button\""), true, "the archive button carries its own class for styling/click-routing")
expect(archiveButtonHTML.contains(">Archive<"), false, "the button's visible content is an icon glyph, not the word \"Archive\"")

// The button renders identically off an open (not-done) block too — nothing here gates
// on isDone; that gate was removed from the caller (DashboardRenderer.renderTask), not
// added here.
let archiveButtonOpenHTML = DashboardTaskRenderer.renderArchiveButton(bare)
expect(
    archiveButtonOpenHTML.contains("class=\"archive-button\""), true,
    "the archive button renders the same for an open task — archiving is no longer done-only"
)

// MARK: - DashboardTaskRenderer.humanDue (C1 — human-readable due chip)

// The raw ISO date (`2026-09-10`) reads fine in a file but not at a glance in a chip —
// `humanDue` gives the due chip's visible text a human phrasing, computed against
// `today`. All against `blockToday` (2026-08-12, a Wednesday).
expect(DashboardTaskRenderer.humanDue(blockToday, today: blockToday), "Today", "a due date equal to today reads \"Today\"")
expect(
    DashboardTaskRenderer.humanDue(blockToday.adding(days: 1), today: blockToday), "Tomorrow",
    "a due date one day after today reads \"Tomorrow\""
)
expect(
    DashboardTaskRenderer.humanDue(blockToday.adding(days: -1), today: blockToday), "Yesterday",
    "a due date one day before today reads \"Yesterday\""
)
expect(
    DashboardTaskRenderer.humanDue(CalendarDate(iso: "2026-12-25")!, today: blockToday), "Dec 25",
    "a same-year date outside today/tomorrow/yesterday reads \"MMM d\", no year"
)
expect(
    DashboardTaskRenderer.humanDue(CalendarDate(iso: "2027-01-01")!, today: blockToday), "Jan 1, 2027",
    "a different-year date reads \"MMM d, yyyy\", year included"
)

// MARK: - RoutineSignal / SignalNudge (D2 — decision notification + loud failure path)

// A clear day: no file at all. The app never calls `RoutineSignal.parse` with a nonempty
// string here — `nil`/empty input is the documented stand-in for "nothing on disk."
expectNil(RoutineSignal.parse(""), "empty text parses to nil — the clear-day state")
expectNil(RoutineSignal.parse("   \n  \n"), "whitespace-only text also parses to nil")
expect(SignalNudge.decide(for: nil), .none, "no signal at all fires no nudge")

// A needs-decision signal, with two questions.
let decisionSignalText = """
status: needs-decision
at: 2026-08-23T06:02:14-07:00
reason: two calendar events overlap this afternoon
questions:
  - Keep the 2pm client call or the 2pm dentist?
  - Should the loser get rescheduled today or pushed to next week?
"""
let decisionSignal = RoutineSignal.parse(decisionSignalText)!
expect(decisionSignal.status, .needsDecision, "needs-decision status parses")
expect(decisionSignal.reason, "two calendar events overlap this afternoon", "reason parses")
expect(
    decisionSignal.questions,
    ["Keep the 2pm client call or the 2pm dentist?", "Should the loser get rescheduled today or pushed to next week?"],
    "both questions parse, in order"
)
expect(
    decisionSignal.at, ISO8601DateFormatter().date(from: "2026-08-23T06:02:14-07:00"),
    "at: parses as the same instant ISO8601DateFormatter would"
)

let decisionNudge = SignalNudge.decide(for: decisionSignal)
expect(
    decisionNudge,
    .decision(
        reason: "two calendar events overlap this afternoon",
        questions: ["Keep the 2pm client call or the 2pm dentist?", "Should the loser get rescheduled today or pushed to next week?"]
    ),
    "a needs-decision signal maps to a decision nudge carrying the reason and questions"
)

// A failed signal — no questions.
let failedSignalText = """
status: failed
at: 2026-08-23T06:02:14-07:00
reason: Google Calendar auth expired, couldn't read events
"""
let failedSignal = RoutineSignal.parse(failedSignalText)!
expect(failedSignal.status, .failed, "failed status parses")
expect(failedSignal.reason, "Google Calendar auth expired, couldn't read events", "failure reason parses")
expect(failedSignal.questions, [], "a failed signal carries no questions")

let failureNudge = SignalNudge.decide(for: failedSignal)
expect(
    failureNudge, .failure(reason: "Google Calendar auth expired, couldn't read events"),
    "a failed signal maps to a failure nudge carrying the reason"
)
expect(failureNudge == decisionNudge, false, "the failure nudge is distinct from the decision nudge")

// Malformed content: present, non-blank, but no recognizable `status:` — must still be
// loud (a failure nudge), never silently treated as a clear day.
let malformedSignalText = "this file got half-written and doesn't have a status line at all"
let malformedSignal = RoutineSignal.parse(malformedSignalText)!
expect(malformedSignal.status, .malformed, "unparseable-but-present content is tagged .malformed, not dropped")

let malformedNudgeIsFailure: Bool
if case .failure = SignalNudge.decide(for: malformedSignal) { malformedNudgeIsFailure = true } else { malformedNudgeIsFailure = false }
expect(malformedNudgeIsFailure, true, "a malformed signal maps to a failure nudge, not silence or a decision nudge")

// An unrecognized status value is malformed too, not silently coerced to a known case.
let unknownStatusText = "status: something-else\nreason: unrecognized status value"
let unknownStatusSignal = RoutineSignal.parse(unknownStatusText)
expect(unknownStatusSignal?.status, .malformed, "an unrecognized status: value parses as .malformed")

// MARK: - Dashboard (B6 — completed-today tasks linger until the 6am rollover)

// A task completed *today* keeps its due-based section instead of vanishing the
// instant you tick it (DESIGN.md → "The panel"; DECISIONS.md 2026-09-09), rendered
// struck-through and sorted below the open items. Listed done-before-open in the raw
// markdown so a passing order check proves an actual sort, not a lucky parse order.
let lingeringTasks = """
- [x] Completed today
      @2026-08-12 · manual · ✓2026-08-12
- [ ] Open task, due today
      @2026-08-12 · manual
"""
let lingeringDash = DashboardComposer.compose(
    brief: "", tasksMarkdown: lingeringTasks, longtermMarkdown: "", today: dashToday
)
expect(lingeringDash.today.count, 2, "the completed-today task stays in Today alongside the open one")
expect(
    lingeringDash.today.map(\.block.text), ["Open task, due today", "Completed today"],
    "open items sort above the completed-today item"
)
expect(lingeringDash.today.last?.block.isDone, true, "the lingering task is still marked done")
let lingeringLabel = DashboardTaskRenderer.render(lingeringDash.today.last!.block, today: dashToday)
expect(lingeringLabel.contains("class=\"label done\""), true, "a completed-today row renders struck-through (the done label class)")
let openLabel = DashboardTaskRenderer.render(lingeringDash.today.first!.block, today: dashToday)
expect(openLabel.contains("done"), false, "an open row carries no done class")

// Completed *yesterday* does not linger — only a completion matching `today` qualifies.
let yesterdayDoneTasks = "- [x] Completed yesterday\n      @2026-08-11 · manual · ✓2026-08-11"
let yesterdayDoneDash = DashboardComposer.compose(
    brief: "", tasksMarkdown: yesterdayDoneTasks, longtermMarkdown: "", today: dashToday
)
expect(yesterdayDoneDash.today.count, 0, "a task completed yesterday does not show")

// An undated `[x]` (hand-edited, no ✓done stamp) can't be tied to "today," so it never shows.
let undatedDoneTasks = "- [x] Hand-ticked, no stamp\n      @2026-08-12 · manual"
let undatedDoneDash = DashboardComposer.compose(
    brief: "", tasksMarkdown: undatedDoneTasks, longtermMarkdown: "", today: dashToday
)
expect(undatedDoneDash.today.count, 0, "an undated completed task does not show")

// Un-ticking a lingering completion returns it to a normal open row.
let reopenedLines = TaskBlock.toggling(
    "- [x] Completed today\n      @2026-08-12 · manual · ✓2026-08-12".components(separatedBy: "\n"),
    at: 0, checked: false, today: dashToday
)!.joined(separator: "\n")
let reopenedDash = DashboardComposer.compose(
    brief: "", tasksMarkdown: reopenedLines, longtermMarkdown: "", today: dashToday
)
expect(reopenedDash.today.count, 1, "un-ticking keeps the task visible")
expect(reopenedDash.today.first?.block.isDone, false, "un-ticking returns it to an open row")

// Long-term included: a completed-today goal in longterm.md also lingers, sorted below
// the open ones — again listed done-first in the raw markdown to prove the sort.
let lingeringLongterm = """
- [x] Ship v1
      @2026-08-12 · manual · ✓2026-08-12
- [ ] Ship v2
      @2027-01-01 · manual
"""
let lingeringLongtermDash = DashboardComposer.compose(
    brief: "", tasksMarkdown: "", longtermMarkdown: lingeringLongterm, today: dashToday
)
expect(lingeringLongtermDash.longTerm.count, 2, "Long-term also shows a completed-today goal")
expect(lingeringLongtermDash.longTerm.first?.block.text, "Ship v2", "the open goal sorts first")
expect(lingeringLongtermDash.longTerm.last?.block.text, "Ship v1", "the completed-today goal sorts below it")

// Across the 6am rollover: a task completed "today" drops once `effectiveToday` advances
// to the next day — no timer, no cleanup pass, since bucketing uses the same
// rollover-aware "today" B5 introduced.
let beforeRollover = CalendarDate.effectiveToday(in: newYork, now: localDate(2026, 8, 12, 23, 59, timeZone: newYork))
let afterRollover = CalendarDate.effectiveToday(in: newYork, now: localDate(2026, 8, 13, 6, 0, timeZone: newYork))
let rolloverTask = "- [x] Ticked late last night\n      @2026-08-12 · manual · ✓\(beforeRollover)"
expect(
    DashboardComposer.compose(brief: "", tasksMarkdown: rolloverTask, longtermMarkdown: "", today: beforeRollover).today.count,
    1, "still lingers before the 6am rollover"
)
expect(
    DashboardComposer.compose(brief: "", tasksMarkdown: rolloverTask, longtermMarkdown: "", today: afterRollover).today.count,
    0, "drops once effectiveToday advances past the rollover"
)

// Correct across a DST boundary: a task completed the day DST begins still lingers when
// `effectiveToday` is that same day, and drops the day after.
let beforeDST = CalendarDate.effectiveToday(in: newYork, now: localDate(2026, 3, 7, 12, 0, timeZone: newYork))
let afterDST = CalendarDate.effectiveToday(in: newYork, now: localDate(2026, 3, 8, 12, 0, timeZone: newYork))
let dstTask = "- [x] Done just before DST\n      @\(beforeDST) · manual · ✓\(beforeDST)"
expect(
    DashboardComposer.compose(brief: "", tasksMarkdown: dstTask, longtermMarkdown: "", today: beforeDST).today.count,
    1, "lingers on the day it was completed, DST boundary notwithstanding"
)
expect(
    DashboardComposer.compose(brief: "", tasksMarkdown: dstTask, longtermMarkdown: "", today: afterDST).today.count,
    0, "drops the day after, across the DST boundary"
)

// MARK: - Accessible checkbox semantics (X2 — Accessibility pass)

// A plain <input type="checkbox"> with no label reads to VoiceOver as just "checkbox",
// with no indication of which task or whether it's already ticked (ROADMAP.md → Hazards
// → Accessibility). `renderCheckbox` fixes that with an explicit role, an aria-checked
// that mirrors `isDone`, and an aria-label carrying the task sentence as the accessible
// name — asserted against the rendered HTML string, same as B4's tidy-render tests above.
let openCheckbox = DashboardTaskRenderer.renderCheckbox(fullBlock)
expect(openCheckbox.contains("role=\"checkbox\""), true, "an open task's checkbox carries role=\"checkbox\"")
expect(openCheckbox.contains("aria-checked=\"false\""), true, "an open task's checkbox reports aria-checked=\"false\"")
expect(openCheckbox.contains(" checked>"), false, "an open task's checkbox has no checked attribute")
expect(
    openCheckbox.contains("aria-label=\"Prep the client deck\""), true,
    "an open task's checkbox carries the task sentence as its accessible name"
)

// The B6 "completed-today lingers" fixture already proves a done block; reuse it here so
// aria-checked is asserted against a real done row, not a hand-built one.
let doneCheckbox = DashboardTaskRenderer.renderCheckbox(lingeringDash.today.last!.block)
expect(doneCheckbox.contains("role=\"checkbox\""), true, "a done task's checkbox carries role=\"checkbox\"")
expect(doneCheckbox.contains("aria-checked=\"true\""), true, "a done task's checkbox reports aria-checked=\"true\", matching isDone")
expect(
    doneCheckbox.contains(" checked>"), true,
    "a done task's checkbox still carries the native checked attribute (click-to-toggle relies on it — must not regress)"
)
expect(
    doneCheckbox.contains("aria-label=\"Completed today\""), true,
    "a done task's checkbox carries its task sentence as its accessible name"
)

// Quotes/HTML in a task sentence must not break out of the aria-label attribute.
let quotedBlock = TaskBlock.parse("- [ ] Say \"hi\" & <wave>\n      @2026-08-12 · manual", today: dashToday)!
let quotedCheckbox = DashboardTaskRenderer.renderCheckbox(quotedBlock)
expect(
    quotedCheckbox.contains("aria-label=\"Say &quot;hi&quot; &amp; &lt;wave&gt;\""), true,
    "quotes/HTML in a task sentence are escaped in aria-label rather than left to break the attribute"
)

// No B6 regression: the wrapped row's tidy label keeps its `done` class alongside the
// new accessible checkbox.
expect(
    DashboardTaskRenderer.render(lingeringDash.today.last!.block, today: dashToday).contains("class=\"label done\""),
    true, "a completed-today row's label still carries the done class (no B6 regression)"
)

// MARK: - BriefStamp (D1 — freshness stamp)

// Parses the build-time stamp from brief.md's first line — driving the instant
// explicitly (a fixed `TimeZone`), never off the wall clock.
let stampBrief = "<!-- built: 2026-08-22T06:03:11-07:00 -->\n# Brief\n\nShipped the deck."
switch BriefStamp.parse(stampBrief) {
case .known(let parsedDate):
    let pacific = TimeZone(identifier: "America/Los_Angeles")!
    var pacificCalendar = Calendar(identifier: .gregorian)
    pacificCalendar.timeZone = pacific
    let parts = pacificCalendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: parsedDate)
    expect(parts.year, 2026, "parses the stamp's year")
    expect(parts.month, 8, "parses the stamp's month")
    expect(parts.day, 22, "parses the stamp's day")
    expect(parts.hour, 6, "parses the stamp's hour in its own offset")
    expect(parts.minute, 3, "parses the stamp's minute")
    expect(parts.second, 11, "parses the stamp's second")
case .unknown:
    failures.append("BriefStamp.parse: a well-formed stamp should parse as .known, got .unknown")
}

// A missing stamp — brief.md with no first-line comment at all — is `.unknown`, never a
// fabricated time.
expect(
    BriefStamp.parse("# Brief\n\nNo stamp here."), .unknown,
    "a brief with no build-stamp line parses as unknown"
)
expect(BriefStamp.parse(""), .unknown, "an empty brief parses as unknown")

// A malformed stamp — right shape, unparseable payload — is likewise unknown, not a guess.
expect(
    BriefStamp.parse("<!-- built: not-a-real-date -->\n# Brief"), .unknown,
    "a malformed stamp payload parses as unknown"
)
expect(
    BriefStamp.parse("<!-- built: 2026-13-40T99:99:99+00:00 -->\n# Brief"), .unknown,
    "an out-of-range stamp payload parses as unknown"
)

// The formatter renders the expected "built h:mma" string for a known instant, driven by
// an explicit `DateComponents` + `TimeZone` — never the wall clock.
var knownStampComponents = DateComponents()
knownStampComponents.year = 2026
knownStampComponents.month = 8
knownStampComponents.day = 22
knownStampComponents.hour = 7
knownStampComponents.minute = 58
knownStampComponents.second = 0
let knownStampZone = TimeZone(identifier: "America/Los_Angeles")!
var knownStampCalendar = Calendar(identifier: .gregorian)
knownStampCalendar.timeZone = knownStampZone
let knownStampInstant = knownStampCalendar.date(from: knownStampComponents)!
expect(
    BriefStamp.known(knownStampInstant).displayString(timeZone: knownStampZone), "built 7:58am",
    "formats a known instant as \"built h:mma\""
)

// A single-digit minute still renders two digits ("built 6:03am", not "built 6:3am").
knownStampComponents.minute = 3
let paddedMinuteInstant = knownStampCalendar.date(from: knownStampComponents)!
expect(
    BriefStamp.known(paddedMinuteInstant).displayString(timeZone: knownStampZone), "built 7:03am",
    "pads a single-digit minute"
)

// The unknown state renders a clear stale/unknown label, never a fake time.
expect(BriefStamp.unknown.displayString(), "build time unknown", "unknown state renders a clear label, not a fabricated time")

// Stripping the stamp line leaves the rest of the brief untouched, whether or not the
// stamp itself parsed.
expect(
    BriefStamp.stripStampLine(from: stampBrief), "# Brief\n\nShipped the deck.",
    "strips a well-formed stamp line, leaving the rest of the brief intact"
)
expect(
    BriefStamp.stripStampLine(from: "<!-- built: garbage -->\n# Brief"), "# Brief",
    "strips a malformed stamp line too — it's still a stamp line, not brief prose"
)
expect(
    BriefStamp.stripStampLine(from: "# Brief\n\nNo stamp here."), "# Brief\n\nNo stamp here.",
    "a brief with no stamp line is returned unchanged"
)

// MARK: - BriefStamp.stripLeadingBriefHeading (double "Brief" heading fix)

// The panel draws its own "Brief" section title; an older brief.md that still opens with
// its own `# Brief` heading must have that heading stripped so the two don't stack.
expect(
    BriefStamp.stripLeadingBriefHeading(from: "# Brief\n\nShipped the deck."), "Shipped the deck.",
    "strips a leading level-1 \"Brief\" heading"
)
expect(
    BriefStamp.stripLeadingBriefHeading(from: "## Brief\n\nShipped the deck."), "Shipped the deck.",
    "strips a leading heading at any # level, not just level-1"
)
expect(
    BriefStamp.stripLeadingBriefHeading(from: "# BRIEF\n\nShipped the deck."), "Shipped the deck.",
    "matches \"Brief\" case-insensitively"
)
expect(
    BriefStamp.stripLeadingBriefHeading(from: "Shipped the deck, no heading."), "Shipped the deck, no heading.",
    "a brief with no leading heading at all is returned unchanged"
)
expect(
    BriefStamp.stripLeadingBriefHeading(from: "# Today\n\nShipped the deck."), "# Today\n\nShipped the deck.",
    "a leading heading with different text is left alone — only \"Brief\" is redundant"
)
expect(
    BriefStamp.stripLeadingBriefHeading(from: "Shipped the deck.\n\n# Brief"), "Shipped the deck.\n\n# Brief",
    "only a *leading* \"Brief\" heading is stripped — one later in the body survives"
)

// `DashboardRenderer.renderBrief` (Sources/Foolscap) composes exactly these FoolscapCore
// primitives — parse the stamp, strip the stamp line, strip a redundant leading "Brief"
// heading, then hand the rest to `MarkdownRenderer` — before wrapping the result in its
// own "<h2>Brief ...</h2>" section title. The selftest target deliberately carries no
// AppKit dependency (see Package.swift) so it can't import `Foolscap` and call
// `renderBrief` directly; reconstructing its exact pipeline here proves the same thing —
// an old brief.md that still opens with its own "# Brief" heading no longer stacks a
// second "Brief" title under the panel's own one, and the prose still renders.
let doubleHeadingBrief = "<!-- built: 2026-08-22T06:03:11-07:00 -->\n# Brief\n\nShipped the deck and prepped the agenda for tomorrow."
let doubleHeadingStripped = BriefStamp.stripStampLine(from: doubleHeadingBrief).trimmingCharacters(in: .whitespacesAndNewlines)
let doubleHeadingTrimmed = BriefStamp.stripLeadingBriefHeading(from: doubleHeadingStripped)
let doubleHeadingBody = MarkdownRenderer.renderHTML(from: doubleHeadingTrimmed)
let doubleHeadingSection = "<section class=\"brief\">\n<h2>Brief <span class=\"freshness\">built 6:03am</span></h2>\n\(doubleHeadingBody)</section>\n"

expect(
    doubleHeadingSection.components(separatedBy: "<h2>Brief").count - 1, 1,
    "a brief.md that still opens with its own \"# Brief\" heading yields exactly one <h2>Brief ...> section title, not two"
)
expect(
    doubleHeadingBody.contains("Shipped the deck and prepped the agenda for tomorrow"), true,
    "the prose after a stripped leading heading still renders"
)
expect(doubleHeadingBody.contains("<h1>"), false, "the leading \"# Brief\" heading itself is gone, not just downgraded")

// MARK: - Report

if failures.isEmpty {
    print("PASS — \(checks) checks")
    exit(0)
} else {
    print("FAIL — \(failures.count) of \(checks) checks\n")
    for failure in failures { print(failure, terminator: "\n\n") }
    exit(1)
}
