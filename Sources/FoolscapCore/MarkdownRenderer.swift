import Foundation
import Markdown

/// Renders a note's markdown to the HTML `Resources/themes/*.css` themes expect.
///
/// Most nodes get a direct, structural HTML translation. GFM task-list items are the one
/// special case: swift-markdown's AST only knows a list item is checked or unchecked, not
/// the `due:`/`done:`/`every:` fields Foolscap attaches to a task line. So for a task item
/// we go back to the item's *source* line (via its parsed `range`) and re-parse it with
/// `TaskLine`, which is what actually knows the date semantics — this is why the renderer
/// lives in `FoolscapCore` next to `TaskLine` rather than being a dumb converter.
public enum MarkdownRenderer {
    public static func renderHTML(
        from markdown: String,
        today: CalendarDate = .today(),
        soonWithinDays: Int = Config.defaultSoonWithinDays
    ) -> String {
        let document = Document(parsing: markdown)
        var visitor = HTMLVisitor(
            sourceLines: markdown.components(separatedBy: "\n"),
            today: today,
            soonWithinDays: soonWithinDays
        )
        return visitor.visit(document)
    }
}

private struct HTMLVisitor: MarkupVisitor {
    let sourceLines: [String]
    let today: CalendarDate
    let soonWithinDays: Int

    // MARK: - Structure

    mutating func defaultVisit(_ markup: Markup) -> String {
        renderChildren(of: markup)
    }

    mutating func visitDocument(_ document: Document) -> String {
        renderChildren(of: document)
    }

    mutating func visitHeading(_ heading: Heading) -> String {
        let level = min(max(heading.level, 1), 6)
        return "<h\(level)>\(renderChildren(of: heading))</h\(level)>\n"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        "<p>\(renderChildren(of: paragraph))</p>\n"
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        "<blockquote>\n\(renderChildren(of: blockQuote))</blockquote>\n"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String {
        "<hr>\n"
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        let cls = codeBlock.language.map { " class=\"language-\(Self.escape($0))\"" } ?? ""
        return "<pre><code\(cls)>\(Self.escape(codeBlock.code))</code></pre>\n"
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) -> String {
        // Raw HTML in a note is rare and not something we trust; render it as text, not markup.
        Self.escape(html.rawHTML)
    }

    // MARK: - Lists / tasks

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> String {
        var html = ""
        for item in unorderedList.listItems { html += visitListItem(item) }
        let cls = Self.isAllTasks(unorderedList.listItems) ? " class=\"tasks\"" : ""
        return "<ul\(cls)>\n\(html)</ul>\n"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> String {
        var html = ""
        for item in orderedList.listItems { html += visitListItem(item) }
        let cls = Self.isAllTasks(orderedList.listItems) ? " class=\"tasks\"" : ""
        return "<ol\(cls)>\n\(html)</ol>\n"
    }

    /// A list is a task list (and gets the flush `.tasks` styling instead of default bullet
    /// indent) only when *every* item is a checkbox — a list mixing tasks and plain bullets
    /// keeps normal indent so the plain items still read as a list.
    private static func isAllTasks(_ items: LazyMapSequence<MarkupChildren, ListItem>) -> Bool {
        var sawItem = false
        for item in items {
            guard item.checkbox != nil else { return false }
            sawItem = true
        }
        return sawItem
    }

    mutating func visitListItem(_ listItem: ListItem) -> String {
        if let checkbox = listItem.checkbox, let (line, task) = taskLine(for: listItem) {
            return renderTask(checkbox: checkbox, task: task, line: line)
        }
        // Tight (single-paragraph) items skip the inner <p> for normal list spacing.
        if listItem.childCount == 1, let paragraph = listItem.child(at: 0) as? Paragraph {
            return "<li>\(renderChildren(of: paragraph))</li>\n"
        }
        return "<li>\(renderChildren(of: listItem))</li>\n"
    }

    /// Recovers the raw source line for a list item (via its parsed `range`) and re-parses
    /// it as a `TaskLine`, so `due:`/`done:`/`every:` fields survive into the rendered task.
    /// The 1-based line number is also handed back so the rendered task can carry it as
    /// `data-line`, letting the panel report which source line a checkbox click came from.
    private func taskLine(for listItem: ListItem) -> (line: Int, task: TaskLine)? {
        guard let line = listItem.range?.lowerBound.line,
              line >= 1, line <= sourceLines.count,
              let task = TaskLine.parse(sourceLines[line - 1])
        else { return nil }
        return (line, task)
    }

    private func renderTask(checkbox: Checkbox, task: TaskLine, line: Int) -> String {
        let isChecked = checkbox == .checked
        let taskClass = isChecked ? " done" : ""
        let checkedAttr = isChecked ? " checked" : ""
        let label = Self.escape(task.text)

        var dueSpan = ""
        if let due = task.due {
            let urgencyClass: String
            switch task.urgency(on: today, soonWithinDays: soonWithinDays) {
            case .soon: urgencyClass = " due-soon"
            case .overdue, .dueToday: urgencyClass = " due-over"
            case .later, .none: urgencyClass = ""
            }
            dueSpan = "<span class=\"due\(urgencyClass)\">\(Self.escape(due.description))</span>"
        }

        // `data-line` lets the panel's injected checkbox listener report which source line
        // to toggle, without trusting anything else about the DOM's stale copy of the note.
        return """
        <div class="task\(taskClass)" data-line="\(line)"><input type="checkbox"\(checkedAttr)><span class="label">\(label)</span>\(dueSpan)</div>

        """
    }

    // MARK: - Tables

    mutating func visitTable(_ table: Table) -> String {
        var html = "<table>\n<thead>\n\(visitTableRowLike(table.head))</thead>\n<tbody>\n"
        for row in table.body.rows { html += visitTableRowLike(row, cellTag: "td") }
        html += "</tbody>\n</table>\n"
        return html
    }

    private mutating func visitTableRowLike(_ row: some TableCellContainer, cellTag: String = "th") -> String {
        var html = "<tr>"
        for cell in row.cells {
            html += "<\(cellTag)>\(renderChildren(of: cell))</\(cellTag)>"
        }
        html += "</tr>\n"
        return html
    }

    // MARK: - Inline

    mutating func visitText(_ text: Text) -> String {
        Self.escape(text.string)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) -> String {
        "<em>\(renderChildren(of: emphasis))</em>"
    }

    mutating func visitStrong(_ strong: Strong) -> String {
        "<strong>\(renderChildren(of: strong))</strong>"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String {
        "<del>\(renderChildren(of: strikethrough))</del>"
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
        "<code>\(Self.escape(inlineCode.code))</code>"
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> String {
        Self.escape(inlineHTML.rawHTML)
    }

    mutating func visitLink(_ link: Link) -> String {
        let href = Self.escapeAttribute(link.destination ?? "")
        return "<a href=\"\(href)\">\(renderChildren(of: link))</a>"
    }

    mutating func visitImage(_ image: Image) -> String {
        let src = Self.escapeAttribute(image.source ?? "")
        let alt = Self.escapeAttribute(Self.plainText(of: image))
        return "<img src=\"\(src)\" alt=\"\(alt)\">"
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String { "<br>\n" }
    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String { "\n" }

    // MARK: - Helpers

    private mutating func renderChildren(of markup: Markup) -> String {
        var html = ""
        for child in markup.children { html += visit(child) }
        return html
    }

    private static func plainText(of markup: Markup) -> String {
        if let text = markup as? Text { return text.string }
        var result = ""
        for child in markup.children { result += plainText(of: child) }
        return result
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
