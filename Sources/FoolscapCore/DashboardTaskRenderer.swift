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
    public static func render(_ block: TaskBlock) -> String {
        // A completed-today task lingers in its bucket rather than vanishing (ROADMAP
        // B6) — the `done` class is what the frosted theme hooks the struck-through/
        // dimmed treatment on.
        let doneClass = block.isDone ? " done" : ""
        var html = "<span class=\"label\(doneClass)\">\(escape(block.text))</span>"

        if let due = block.due {
            html += "<span class=\"due\">\(escape(due.description))</span>"
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

    /// Plain glyphs, not images — the panel has no attachments pipeline for icons, and a
    /// muted emoji reads fine at 10.5px next to the other faint chips.
    private static func icon(for source: TaskBlock.Source) -> String {
        switch source {
        case .calendar: return "📅"
        case .chat: return "💬"
        case .manual: return "✎"
        }
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
}
