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

// A checked/done task never shows in either bucket — Brief is the only place done work
// shows (DESIGN.md → The panel).
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

// MARK: - Report

if failures.isEmpty {
    print("PASS — \(checks) checks")
    exit(0)
} else {
    print("FAIL — \(failures.count) of \(checks) checks\n")
    for failure in failures { print(failure, terminator: "\n\n") }
    exit(1)
}
