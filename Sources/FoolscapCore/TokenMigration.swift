import Foundation

/// The one-time on-disk migration for the `★` → `today` placement-token rename
/// (DECISIONS.md 2026-09-11 — "the on-disk placement token is renamed `★` → `today`").
/// `TaskBlock.applyMetadata` accepts both spellings permanently, so correctness never
/// depends on this having run; it exists only to stop `tasks.md`/`longterm.md`/archive
/// shards from lingering with a glyph the UI no longer shows.
public enum TokenMigration {
    /// Re-renders every task block whose raw metadata line still carries the legacy `★`
    /// token, through `TaskBlock.rendered()` — the same canonical re-render
    /// `toggling`/`settingFocus` already produce — so the token comes out as `today` in
    /// its usual field slot and the rest of the block's fields stay exactly where
    /// `rendered()` always places them. Blocks with no `★` are left as their original raw
    /// lines, byte-for-byte, so a file that's already clean (or has no tasks at all) never
    /// gets rewritten.
    ///
    /// Returns `nil` when `markdown` has no `★` anywhere — the caller's signal to skip the
    /// write entirely — which also makes this idempotent: running it again on its own
    /// output finds nothing left to migrate.
    public static func migrate(_ markdown: String, today: CalendarDate = .today()) -> String? {
        guard markdown.contains("★") else { return nil }

        var lines = markdown.components(separatedBy: "\n")
        var index = 0
        var changed = false
        while index < lines.count {
            guard let (block, consumed) = TaskBlock.parse(lines, at: index, today: today) else {
                index += 1
                continue
            }
            if lines[index..<(index + consumed)].contains(where: { $0.contains("★") }) {
                let rendered = block.rendered().components(separatedBy: "\n")
                lines.replaceSubrange(index..<(index + consumed), with: rendered)
                index += rendered.count
                changed = true
            } else {
                index += consumed
            }
        }
        return changed ? lines.joined(separator: "\n") : nil
    }
}
