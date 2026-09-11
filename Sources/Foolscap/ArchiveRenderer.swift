import Foundation
import FoolscapCore

/// The minimal archive viewer (DECISIONS.md 2026-09-11 — keep it low-risk: there is no
/// second-window precedent in this codebase, so this reuses the single `NoteWindow`'s
/// existing `webView` instead of standing up a second `WKWebView`/config). Renders the
/// CURRENT month's archive shard as a plain list with a Restore button per row and a
/// "Back to dashboard" control. Multi-month navigation/date-picker is deferred — a later
/// slice, once there's more than one month of history worth browsing.
enum ArchiveRenderer {
    static func renderBody(_ shardMarkdown: String, shardFile: String, today: CalendarDate) -> String {
        let tasks = parseArchivedBlocks(shardMarkdown)
        var html = "<div class=\"dashboard archive\">\n"
        html += "<section class=\"section\">\n"
        html += "<h2>Archive</h2>\n"
        html += "<button type=\"button\" class=\"back-to-dashboard\">← Back to dashboard</button>\n"
        if tasks.isEmpty {
            html += "<p class=\"empty\">Nothing archived this month.</p>\n"
        } else {
            html += "<ul class=\"tasks\">\n"
            for (block, line) in tasks {
                html += renderArchivedRow(block, line: line, file: shardFile, today: today)
            }
            html += "</ul>\n"
        }
        html += "</section>\n</div>\n"
        return html
    }

    /// `data-file`/`data-line` carry the archive shard's own relative path (`archive/
    /// YYYY-MM.md`) and 1-based source line, the same write-back contract
    /// `DashboardRenderer.renderTask` uses — `restoreTask` in `AppDelegate` reads them
    /// back off the click the same way `toggleTask`/`archiveTask` already do.
    ///
    /// Now that archiving isn't gated on done (DECISIONS.md 2026-09-11, widened), an
    /// archived row needs its own "was it done" tell: the same checkbox the dashboard
    /// uses (checked/unchecked mirrors `isDone` as it stood at archive time), rendered
    /// `disabled` since this shard has no toggle write-back, plus the same `.task.done`
    /// dimming/strikethrough the dashboard already gives a completed row — no new CSS.
    private static func renderArchivedRow(_ block: TaskBlock, line: Int, file: String, today: CalendarDate) -> String {
        let checkbox = DashboardTaskRenderer.renderCheckbox(block, disabled: true)
        let tidy = DashboardTaskRenderer.render(block, today: today)
        let restoreButton = "<button type=\"button\" class=\"restore-button\""
            + " aria-label=\"Restore: \(escapeAttribute(block.text))\""
            + " title=\"Restore\">Restore</button>"
        let doneClass = block.isDone ? " done" : ""
        return """
        <li class="task\(doneClass)" data-file="\(escape(file))" data-line="\(line)">\(checkbox)\(tidy)\(restoreButton)</li>

        """
    }

    /// Scans every checkbox block in the shard, tagging each with its 1-based source
    /// line — same shape as `DashboardComposer`'s own block scan.
    private static func parseArchivedBlocks(_ markdown: String) -> [(TaskBlock, Int)] {
        let lines = markdown.components(separatedBy: "\n")
        var results: [(TaskBlock, Int)] = []
        var index = 0
        while index < lines.count {
            if let (block, consumed) = TaskBlock.parse(lines, at: index) {
                results.append((block, index + 1))
                index += consumed
            } else {
                index += 1
            }
        }
        return results
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
