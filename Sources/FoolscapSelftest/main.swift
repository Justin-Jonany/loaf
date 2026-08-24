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

// MARK: - Report

if failures.isEmpty {
    print("PASS — \(checks) checks")
    exit(0)
} else {
    print("FAIL — \(failures.count) of \(checks) checks\n")
    for failure in failures { print(failure, terminator: "\n\n") }
    exit(1)
}
