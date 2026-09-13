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
            // Done-ness is not a reason to exclude a task — a completed task stays in its
            // @due bucket, struck-through, until the user archives it (DECISIONS.md
            // 2026-09-12).
            guard let due = task.block.due else { continue }

            if task.block.focus {
                // A starred task is pulled into Today regardless of @due (B7 — Curated
                // Today) — @due is left untouched, it just stops driving the bucket.
                todayBucket.append(task)
            } else if due <= today {
                // Spillover (overdue) + due-tonight both read as "Today."
                todayBucket.append(task)
            } else if today.days(until: due) <= weekLookaheadDays {
                // Not already claimed by Today — each task renders in exactly one
                // bucket, most-urgent-or-starred wins. That's the dedup.
                weekBucket.append(task)
            }
        }

        var longTermBucket: [DashboardTask] = []
        for task in parseBlocks(longtermMarkdown, sourceFile: "longterm.md", today: today) {
            guard task.block.due != nil else { continue }
            // Same star pull-forward as tasks.md: a focused long-term goal shows up in
            // Today rather than waiting in Long-term (B7 — Curated Today).
            if task.block.focus {
                todayBucket.append(task)
            } else {
                longTermBucket.append(task)
            }
        }

        // Buckets are returned in parse order — a completed task keeps its position
        // rather than sorting to the bottom on completion (DECISIONS.md 2026-09-11,
        // reversing the earlier B6 "sorts to the bottom" call).
        return Dashboard(
            brief: brief,
            today: todayBucket,
            thisWeek: weekBucket,
            longTerm: longTermBucket
        )
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
