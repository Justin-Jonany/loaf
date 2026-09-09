import Foundation

/// A task bucketed onto the dashboard, with enough provenance (`sourceFile`, `line`) for
/// a later write-back path (A4) to find its way back to the exact line it came from.
public struct DashboardTask: Equatable, Sendable {
    public var block: TaskBlock
    /// `"tasks.md"` or `"longterm.md"` — never a path, just the known filename.
    public var sourceFile: String
    /// 1-based line number of the block's checkbox line within `sourceFile`.
    public var line: Int

    public init(block: TaskBlock, sourceFile: String, line: Int) {
        self.block = block
        self.sourceFile = sourceFile
        self.line = line
    }
}

/// The composed dashboard: the four sections the panel shows (DESIGN.md → "The panel — a
/// composed dashboard"). Nothing here is a folder listing — it is always exactly these
/// four sections, built from exactly three known files.
public struct Dashboard: Equatable, Sendable {
    public var brief: String
    public var today: [DashboardTask]
    public var thisWeek: [DashboardTask]
    public var longTerm: [DashboardTask]

    public init(brief: String, today: [DashboardTask], thisWeek: [DashboardTask], longTerm: [DashboardTask]) {
        self.brief = brief
        self.today = today
        self.thisWeek = thisWeek
        self.longTerm = longTerm
    }
}

/// Reads `brief.md`, `tasks.md`, `longterm.md` and buckets their unchecked tasks into the
/// dashboard's four sections. Pure logic, no AppKit — HTML composition for the WKWebView
/// lives in the app/renderer layer (ROADMAP B1).
public enum DashboardComposer {
    /// Default "within the week" lookahead: a sliding 7-day window from `today`, not a
    /// calendar-week boundary — simpler and matches the ticket's "due in 3 days" case
    /// without pulling in `Config.weekStarts` semantics that a real calendar-week bucket
    /// would need.
    public static let defaultWeekLookaheadDays = 7

    /// Reads exactly the three known files from `vault` — nothing else. A stray file
    /// (`notes.md`, anything else in the vault) is never looked at, let alone read: this
    /// composer only ever asks for `brief.md`/`tasks.md`/`longterm.md` by name. A missing
    /// file reads as empty, not an error — an empty vault still composes a dashboard.
    public static func compose(
        vault: Vault,
        today: CalendarDate = .today(),
        weekLookaheadDays: Int = defaultWeekLookaheadDays
    ) -> Dashboard {
        let brief = (try? vault.read(vault.root.appendingPathComponent("brief.md"))) ?? ""
        let tasksMarkdown = (try? vault.read(vault.root.appendingPathComponent("tasks.md"))) ?? ""
        let longtermMarkdown = (try? vault.read(vault.root.appendingPathComponent("longterm.md"))) ?? ""
        return compose(
            brief: brief,
            tasksMarkdown: tasksMarkdown,
            longtermMarkdown: longtermMarkdown,
            today: today,
            weekLookaheadDays: weekLookaheadDays
        )
    }

    /// The pure bucketing logic, given file contents directly rather than a vault — this
    /// is what the unit tests exercise.
    public static func compose(
        brief: String,
        tasksMarkdown: String,
        longtermMarkdown: String,
        today: CalendarDate = .today(),
        weekLookaheadDays: Int = defaultWeekLookaheadDays
    ) -> Dashboard {
        var todayBucket: [DashboardTask] = []
        var weekBucket: [DashboardTask] = []

        for task in parseBlocks(tasksMarkdown, sourceFile: "tasks.md", today: today) {
            // A task with no @due can't be placed in any bucket (DESIGN.md → The panel).
            // A task ticked today keeps its bucket too (ROADMAP B6) — see `isEligible`.
            guard isEligible(task.block, today: today), let due = task.block.due else { continue }

            if due <= today {
                // Spillover (overdue) + due-tonight both read as "Today."
                todayBucket.append(task)
            } else if today.days(until: due) <= weekLookaheadDays {
                // Not already claimed by Today — each task renders in exactly one
                // bucket, most-urgent wins. That's the dedup.
                weekBucket.append(task)
            }
        }

        let longTermBucket = parseBlocks(longtermMarkdown, sourceFile: "longterm.md", today: today)
            .filter { isEligible($0.block, today: today) && $0.block.due != nil }

        return Dashboard(
            brief: brief,
            today: sortedOpenFirst(todayBucket),
            thisWeek: sortedOpenFirst(weekBucket),
            longTerm: sortedOpenFirst(longTermBucket)
        )
    }

    /// Unchecked, or checked and completed **today** (ROADMAP B6). Ticking a box used to
    /// drop the row the instant it was checked, because every bucket showed only
    /// unchecked tasks — no "I did it" feedback, no in-panel trace of the day's progress.
    /// A completed-today task now keeps its `@due`-based section until the 6am rollover
    /// (DECISIONS.md 2026-09-09). `today` is always the same rollover-aware value the
    /// caller buckets everything else against (`CalendarDate.effectiveToday`), so once it
    /// advances, yesterday's completions stop matching `done == today` and fall off on
    /// their own — no timer, no cleanup pass. A done task with no `✓done` stamp (a
    /// hand-typed `- [x]`) can't be tied to any day, so it never qualifies.
    private static func isEligible(_ block: TaskBlock, today: CalendarDate) -> Bool {
        !block.isDone || block.done == today
    }

    /// Open items first, completed-today items below them (ROADMAP B6: "sorts to the
    /// bottom of that section"). A stable sort, so ties on either side keep their parse
    /// order.
    private static func sortedOpenFirst(_ tasks: [DashboardTask]) -> [DashboardTask] {
        tasks.sorted { !$0.block.isDone && $1.block.isDone }
    }

    /// Scans every checkbox block in `markdown`, tagging each with its 1-based source
    /// line so a later write-back path can find its way back to the exact line.
    private static func parseBlocks(_ markdown: String, sourceFile: String, today: CalendarDate) -> [DashboardTask] {
        let lines = markdown.components(separatedBy: "\n")
        var tasks: [DashboardTask] = []
        var index = 0
        while index < lines.count {
            if let (block, consumed) = TaskBlock.parse(lines, at: index, today: today) {
                tasks.append(DashboardTask(block: block, sourceFile: sourceFile, line: index + 1))
                index += consumed
            } else {
                index += 1
            }
        }
        return tasks
    }
}
