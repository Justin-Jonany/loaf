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
    public static func render(_ block: TaskBlock, today: CalendarDate) -> String {
        // A completed-today task lingers in its bucket rather than vanishing (ROADMAP
        // B6) — the `done` class is what the frosted theme hooks the struck-through/
        // dimmed treatment on.
        let doneClass = block.isDone ? " done" : ""
        var html = "<span class=\"label\(doneClass)\">\(escape(block.text))</span>"

        if let due = block.due {
            // Human phrasing for the chip's visible text (C1 — "Today"/"Tomorrow"/"MMM d"),
            // with the exact ISO date kept in `title` so hovering still shows the real date.
            html += "<span class=\"due\" title=\"\(escape(due.description))\">\(escape(humanDue(due, today: today)))</span>"
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
    /// for the tidy label/chip rendering above.
    public static func renderCheckbox(_ block: TaskBlock) -> String {
        let checkedAttr = block.isDone ? " checked" : ""
        let ariaChecked = block.isDone ? "true" : "false"
        return "<input type=\"checkbox\" role=\"checkbox\" aria-checked=\"\(ariaChecked)\""
            + " aria-label=\"\(escapeAttribute(block.text))\"\(checkedAttr)>"
    }

    /// The per-row focus toggle (ROADMAP B7 — Curated Today: a `★` focus flag). A plain
    /// `<button>` with `aria-pressed` mirroring `block.focus` and an `aria-label` naming
    /// both the action and the task, same accessibility contract as `renderCheckbox`
    /// above. Kept in `FoolscapCore` (rather than the app's `DashboardRenderer`, which
    /// wraps this in the `<li>` that carries the write-back `data-file`/`data-line`
    /// attributes) so `FoolscapSelftest` can assert the ARIA contract directly.
    public static func renderFocusToggle(_ block: TaskBlock) -> String {
        let pressed = block.focus ? "true" : "false"
        let action = block.focus ? "Remove from Today" : "Add to Today"
        let onClass = block.focus ? " on" : ""
        return "<button type=\"button\" class=\"focus-toggle\(onClass)\" aria-pressed=\"\(pressed)\""
            + " aria-label=\"\(escapeAttribute(action)): \(escapeAttribute(block.text))\""
            + " title=\"\(escapeAttribute(action))\">★</button>"
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
