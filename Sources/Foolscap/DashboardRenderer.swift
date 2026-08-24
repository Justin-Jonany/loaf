import Foundation
import FoolscapCore

/// Turns an already-bucketed `Dashboard` (FoolscapCore's pure `DashboardComposer`) into
/// the HTML the WKWebView loads. Composition into HTML is deliberately kept out of
/// FoolscapCore (ROADMAP B1) — this file is the app/renderer layer, plain Foundation, no
/// AppKit.
///
/// Raw `@`/`#`/`!` tokens still show in the rendered metadata line — tidying those into
/// chips/icons is B4, not this ticket.
enum DashboardRenderer {
    static func renderBody(_ dashboard: Dashboard) -> String {
        var html = "<div class=\"dashboard\">\n"
        html += renderBrief(dashboard.brief)
        html += renderSection(title: "Today", tasks: dashboard.today, emptyText: "Nothing due today.")
        html += renderSection(title: "This week", tasks: dashboard.thisWeek, emptyText: "Nothing else due this week.")
        html += renderSection(title: "Long-term", tasks: dashboard.longTerm, emptyText: "No long-term goals yet.")
        html += "</div>\n"
        return html
    }

    /// Brief is free prose from `brief.md` — run through the same markdown renderer as a
    /// note, so basic formatting (paragraphs, emphasis) survives.
    private static func renderBrief(_ brief: String) -> String {
        let trimmed = brief.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = trimmed.isEmpty
            ? "<p class=\"empty\">No brief yet.</p>\n"
            : MarkdownRenderer.renderHTML(from: trimmed)
        return "<section class=\"brief\">\n<h2>Brief</h2>\n\(body)</section>\n"
    }

    private static func renderSection(title: String, tasks: [DashboardTask], emptyText: String) -> String {
        guard !tasks.isEmpty else {
            return """
            <section class="section">
            <h2>\(escape(title))</h2>
            <p class="empty">\(escape(emptyText))</p>
            </section>

            """
        }
        var html = "<section class=\"section\">\n<h2>\(escape(title))</h2>\n<ul class=\"tasks\">\n"
        for task in tasks { html += renderTask(task) }
        html += "</ul>\n</section>\n"
        return html
    }

    /// `data-file`/`data-line` carry enough for a later write-back path (A4) to find its
    /// way back to the source line; nothing wires them up to a click yet — see A4.
    private static func renderTask(_ task: DashboardTask) -> String {
        let block = task.block
        let label = escape(block.text)

        var dueSpan = ""
        if let due = block.due {
            dueSpan = "<span class=\"due\">@\(escape(due.description))</span>"
        }

        var metaTokens: [String] = []
        if let priority = block.priority { metaTokens.append("!\(priority.rawValue)") }
        if let type = block.type { metaTokens.append("#\(type)") }
        metaTokens.append(block.source.rawValue)
        let metaSpan = "<span class=\"meta\">\(escape(metaTokens.joined(separator: " · ")))</span>"

        return """
        <li class="task" data-file="\(escape(task.sourceFile))" data-line="\(task.line)"><input type="checkbox"><span class="label">\(label)</span>\(dueSpan)\(metaSpan)</li>

        """
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
