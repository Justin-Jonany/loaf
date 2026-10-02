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

    /// One shard's calendar month — what the archive viewer pages through. A plain
    /// year/month pair rather than a `Date`, so stepping back and forth is exact integer
    /// arithmetic with no time-of-day or DST edge to slip across a month boundary.
    public struct Month: Equatable, Comparable {
        public let year: Int
        public let month: Int

        public init(year: Int, month: Int) {
            self.year = year
            self.month = month
        }

        /// The month `date` falls in, by the same LOCAL-calendar rule `archiveShardURL` files under.
        public init(containing date: Date, timeZone: TimeZone = .current) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let parts = calendar.dateComponents([.year, .month], from: date)
            self.init(year: parts.year!, month: parts.month!)
        }

        /// Reads a shard filename (`2026-09.md`) back into its month; `nil` for anything else
        /// that can sit in `archive/` (a conflict copy, a stray note).
        public init?(shardFileName name: String) {
            guard name.count == 10, name.hasSuffix(".md") else { return nil }
            let parts = name.dropLast(3).split(separator: "-")
            guard parts.count == 2, parts[0].count == 4, parts[1].count == 2,
                  let year = Int(parts[0]), let month = Int(parts[1]), (1...12).contains(month)
            else { return nil }
            self.init(year: year, month: month)
        }

        public func shifted(by months: Int) -> Month {
            let index = year * 12 + (month - 1) + months
            return Month(year: index / 12, month: index % 12 + 1)
        }

        public var shardFileName: String { String(format: "%04d-%02d.md", year, month) }

        // The rest of the panel's chrome is English-only, so a fixed list keeps the heading
        // deterministic rather than following the system locale.
        private static let names = ["January", "February", "March", "April", "May", "June", "July",
                                    "August", "September", "October", "November", "December"]

        /// "September 2026" — the archive viewer's heading.
        public var title: String { "\(Self.names[month - 1]) \(year)" }

        public static func < (lhs: Month, rhs: Month) -> Bool {
            (lhs.year, lhs.month) < (rhs.year, rhs.month)
        }
    }

    public static func shardURL(for month: Month, vault: Vault) -> URL {
        vault.root.appendingPathComponent("archive").appendingPathComponent(month.shardFileName)
    }

    /// The oldest month with a shard on disk, so the viewer stops paging back once there's
    /// no older history instead of walking into empty months forever. `nil` when nothing
    /// has been archived yet.
    public static func earliestMonth(vault: Vault) -> Month? {
        let dir = vault.root.appendingPathComponent("archive", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.compactMap(Month.init(shardFileName:)).min()
    }
}
