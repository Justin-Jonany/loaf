import Foundation

/// The permanent archive's on-disk location (DECISIONS.md 2026-09-11): "archive storage
/// is sharded markdown, not a database." A completed task moved out of `tasks.md` lands
/// in `<vault>/archive/YYYY-MM.md` — one file per calendar month, kept forever — rather
/// than a keep-forever single file, so the archive viewer only ever loads the month in
/// view and the vault stays greppable plain text.
public enum Archive {
    /// The shard `date` belongs to. No directory-creation here — `Vault.writeAtomically`
    /// already creates intermediate directories on its first write, so `archive/` appears
    /// the first time a task is archived, same as any other vault file.
    ///
    /// Bucketed by the LOCAL calendar month, not UTC: the archive stamp is deliberately an
    /// instant with local-feeling meaning ("when it left the list," TaskBlock.archivedAt's
    /// own doc comment), and grouping by the month a person would actually call "this
    /// month" matters more here than the DST-safety `CalendarDate` arithmetic needs for a
    /// stored due *date* — there's no date-only value being round-tripped through this
    /// calculation to shift.
    public static func archiveShardURL(for date: Date, vault: Vault, timeZone: TimeZone = .current) -> URL {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month], from: date)
        let name = String(format: "%04d-%02d.md", parts.year!, parts.month!)
        return vault.root.appendingPathComponent("archive").appendingPathComponent(name)
    }
}
