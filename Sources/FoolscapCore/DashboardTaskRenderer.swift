import Foundation

/// Renders the tidy display fragment for one task block: the plain sentence, a due-date
/// chip, a faint `#type` tag, a priority dot, and a source icon — with none of the
/// storage-format `@`/`#`/`!` tokens reaching the DOM (DESIGN.md → Tasks: "Display ≠
/// storage"). The caller (the app's `DashboardRenderer`, B1) wraps this fragment in the
/// `<li>` that carries the write-back `data-file`/`data-line` attributes; this piece owns
/// the part that actually hides the storage tokens, so it lives in `FoolscapCore` where
/// `FoolscapSelftest` can assert against it directly — the same split `MarkdownRenderer`
/// already uses for the single-note task view.
public enum DashboardTaskRenderer {
    public static func render(
        _ block: TaskBlock, today: CalendarDate, soonWithinDays: Int = Config.defaultSoonWithinDays
    ) -> String {
        // A completed-today task lingers in its bucket rather than vanishing (ROADMAP
        // B6) — the `done` class is what the frosted theme hooks the struck-through/
        // dimmed treatment on.
        let doneClass = block.isDone ? " done" : ""
        var html = "<span class=\"label\(doneClass)\">\(escape(block.text))</span>"

        if let due = block.due {
            // Urgency drives the chip's class (unlike MarkdownRenderer's single-note view,
            // due-today is deliberately NOT treated as overdue-red here — the panel is a
            // glanceable daily surface, so "due today" and "due soon" read the same, and
            // only a genuinely missed date gets the loud treatment.
            let urgencyClass: String
            switch block.urgency(on: today, soonWithinDays: soonWithinDays) {
            case .overdue: urgencyClass = " due-over"
            case .dueToday, .soon: urgencyClass = " due-soon"
            case .later, .none: urgencyClass = ""
            }
            // Human phrasing for the chip's visible text (C1 — "Today"/"Tomorrow"/"MMM d"),
            // with the exact ISO date kept in `title` so hovering still shows the real date.
            html += "<span class=\"due\(urgencyClass)\" title=\"\(escape(due.description))\">\(escape(humanDue(due, today: today)))</span>"
        }
        if let type = block.type {
            html += "<span class=\"type\">\(escape(type))</span>"
        }
        if let priority = block.priority {
            html += "<span class=\"priority-dot \(priority.rawValue)\" title=\"\(priority.rawValue) priority\"></span>"
        }
        html += "<span class=\"source-icon \(block.source.rawValue)\" title=\"\(block.source.rawValue)\">\(icon(for: block.source))</span>"

        return html
    }

    private static let monthAbbreviations = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]

    /// The due chip's human phrasing (C1), computed against `today` — the raw ISO date
    /// (`2026-09-10`) reads fine in a file but not at a glance in a chip. Built entirely
    /// from `CalendarDate`'s own fields/arithmetic rather than round-tripping through
    /// `Date`: a `Date`-based formatter would need a time zone to turn `due` back into a
    /// day, and picking the wrong instant (midnight? noon?) risks landing on the wrong
    /// side of a DST transition (see `CalendarDate`'s own doc comment on this hazard).
    public static func humanDue(_ due: CalendarDate, today: CalendarDate) -> String {
        if due == today { return "Today" }
        if due == today.adding(days: 1) { return "Tomorrow" }
        if due == today.adding(days: -1) { return "Yesterday" }

        let month = monthAbbreviations[due.month - 1]
        if due.year == today.year {
            return "\(month) \(due.day)"
        }
        return "\(month) \(due.day), \(due.year)"
    }

    /// Plain glyphs, not images — the panel has no attachments pipeline for icons, and a
    /// muted emoji reads fine at 10.5px next to the other faint chips.
    private static func icon(for source: TaskBlock.Source) -> String {
        switch source {
        case .calendar: return "📅"
        case .chat: return "💬"
        case .manual: return "✎"
        }
    }

    /// The accessible `<input type="checkbox">` for a task row (ROADMAP X2 — Accessibility
    /// pass, Hazards → Accessibility). A plain `<input type="checkbox">` with no label gets
    /// announced by VoiceOver as just "checkbox" with no indication of *which* task or
    /// whether it's already ticked — hence explicit `role="checkbox"`, `aria-checked`
    /// mirroring `isDone`, and `aria-label` carrying the task sentence as its accessible
    /// name. Kept in `FoolscapCore` (rather than the app's `DashboardRenderer`, which wraps
    /// this in the `<li>` that carries the write-back `data-file`/`data-line` attributes)
    /// so `FoolscapSelftest` can assert the ARIA contract directly, the same split B4 set up
    /// for the tidy label/chip rendering above. `disabled` is for the archive viewer
    /// (`ArchiveRenderer`), which reuses this same checkbox purely as a was-it-done
    /// indicator on a row that has no write-back for it — undisabled, the box would still
    /// natively flip its own `:checked` state on a stray click even though nothing is
    /// listening for that shard's toggle, leaving the row visually lying about itself
    /// until the next repaint.
    public static func renderCheckbox(_ block: TaskBlock, disabled: Bool = false) -> String {
        let checkedAttr = block.isDone ? " checked" : ""
        let ariaChecked = block.isDone ? "true" : "false"
        let disabledAttr = disabled ? " disabled" : ""
        return "<input type=\"checkbox\" role=\"checkbox\" aria-checked=\"\(ariaChecked)\""
            + " aria-label=\"\(escapeAttribute(block.text))\"\(checkedAttr)\(disabledAttr)>"
    }

    /// The per-row Today-placement control (DECISIONS.md 2026-09-11 — "sticky drag-to-
    /// Today, replacing the `★` focus flag"). The star glyph and its filled `.on` state
    /// are retired: a task's mere presence in the Today section is now the only placement
    /// indicator, so this button shows the same neutral handle glyph regardless of
    /// `block.focus` — it no longer doubles as a badge (a star wrongly connoted
    /// importance, which `!high/!med/!low` priority already owns). It's also the drag
    /// SOURCE the panel's drag-to-Today JS wires up (`draggable`) — scoped to this small
    /// handle, not the whole row, so a drag can't swallow the checkbox/archive-icon click
    /// beside it. Keeps the exact ARIA contract it always had (`aria-pressed` mirroring
    /// `block.focus`, an `aria-label` naming both the action and the task) so a
    /// keyboard/VoiceOver user can still toggle Today-placement by click/Enter without a
    /// mouse drag (ROADMAP X2). Kept in `FoolscapCore` (rather than the app's
    /// `DashboardRenderer`, which wraps this in the `<li>` that carries the write-back
    /// `data-file`/`data-line` attributes) so `FoolscapSelftest` can assert the ARIA
    /// contract directly.
    public static func renderFocusToggle(_ block: TaskBlock) -> String {
        let pressed = block.focus ? "true" : "false"
        let action = block.focus ? "Remove from Today" : "Add to Today"
        return "<button type=\"button\" class=\"focus-toggle\" draggable=\"true\" aria-pressed=\"\(pressed)\""
            + " aria-label=\"\(escapeAttribute(action)): \(escapeAttribute(block.text))\""
            + " title=\"\(escapeAttribute(action))\">⠿</button>"
    }

    /// The per-row "Archive" action (DECISIONS.md 2026-09-11 — the permanent archive,
    /// later widened to any task): moves a task, done or not, off `tasks.md`/
    /// `longterm.md` into the monthly archive shard, preserving whatever `isDone`/
    /// `✓done` state it already carries (`TaskBlock.archiving` doesn't touch either).
    /// Unlike `renderFocusToggle`, this is a one-shot action, not a toggle — no
    /// `aria-pressed`, just a labelled `<button>` naming the action and the task, same
    /// accessible-name contract as `renderCheckbox`/`renderFocusToggle` above. Visible
    /// content is a muted line-art glyph (a downward arrow to a bar — the "file it away"
    /// gesture), monochrome rather than a color emoji, so it sits permanently at the row's
    /// trailing edge (`DashboardRenderer.renderTask` no longer gates this on `block.isDone`)
    /// without reading as a loud text button; `aria-label`/`title` still spell out the
    /// action for VoiceOver/tooltip.
    public static func renderArchiveButton(_ block: TaskBlock) -> String {
        "<button type=\"button\" class=\"archive-button\""
            + " aria-label=\"Archive: \(escapeAttribute(block.text))\""
            + " title=\"Archive\">\u{2913}</button>"
    }

    private static func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            default: result.append(character)
            }
        }
        return result
    }

    private static func escapeAttribute(_ text: String) -> String {
        escape(text).replacingOccurrences(of: "\"", with: "&quot;")
    }
}
