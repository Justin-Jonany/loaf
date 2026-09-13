import Foundation

/// The write-conflict rule for shared vault files (`tasks.md`, `longterm.md` — DESIGN.md
/// → "Files in the vault": Brief is Claude-owned, the lists are shared). The scheduled
/// morning run and the app can both write these, so a plain read-modify-write race can
/// silently clobber one side (ROADMAP.md → Hazards → "Write conflicts on shared files";
/// ticket X1).
///
/// `ConflictDecision.decide` is the pure rule, with no file I/O — fully unit-testable.
/// `ConflictGuard.hasExternalChange` is the one bit of I/O the rule needs (comparing
/// against disk), kept here rather than in `Sources/Loaf` because it composes
/// directly with `Vault`'s self-write registry. Everything below is Foundation-only, no
/// AppKit/WebKit — `Sources/Loaf` wires the actual conflict-copy write and user
/// notice on top of it.
public enum ConflictDecision: Equatable, Sendable {
    /// Disk hasn't changed since we read it — safe to write the app's change straight
    /// through, same as before this guard existed.
    case writeThrough
    /// Disk changed since we read it, but the app has no unsaved change of its own —
    /// nothing to lose, so just pick up what's on disk. No conflict file.
    case reloadClean
    /// Disk changed since we read it *and* the app has an unsaved change — last-write-wins
    /// would silently destroy one side. Keep the on-disk version; the caller saves the
    /// app's version to a `.conflict-<timestamp>.md` sidecar and tells the user.
    case conflictKeepDiskSaveCopy

    /// The rule, given only the two facts that matter. `diskChangedSinceRead` is expected
    /// to already exclude our own writes (see `ConflictGuard.hasExternalChange`, which
    /// consults `Vault.wasSelfWrite`) — a self-write must never be mistaken for the
    /// concurrent external edit this guard exists to catch.
    public static func decide(diskChangedSinceRead: Bool, bufferDirty: Bool) -> ConflictDecision {
        guard diskChangedSinceRead else { return .writeThrough }
        return bufferDirty ? .conflictKeepDiskSaveCopy : .reloadClean
    }
}

/// The `(mtime, size)` of a file at the moment the app read it — cheap enough to check on
/// every save without hashing content. Mirrors the pair `Vault` already records for its
/// self-write registry.
public struct FileSnapshot: Equatable, Sendable {
    public var mtime: Date
    public var size: Int

    public init(mtime: Date, size: Int) {
        self.mtime = mtime
        self.size = size
    }

    /// The current on-disk snapshot of `url`, or `nil` if it can't be stat'd (missing,
    /// permissions, ...) — a caller treats that as "nothing to compare," not a change.
    public static func current(at url: URL) -> FileSnapshot? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let mtime = attrs[.modificationDate] as? Date,
              let size = attrs[.size] as? Int
        else { return nil }
        return FileSnapshot(mtime: mtime, size: size)
    }

    /// `true` if `other` doesn't match this snapshot — something wrote the file since it
    /// was taken.
    public func differs(from other: FileSnapshot) -> Bool {
        other.mtime != mtime || other.size != size
    }
}

/// Detects whether a shared file changed on disk since a snapshot was taken, filtering
/// out our own writes so self-write suppression holds here too (`VaultWatcher` already
/// does this for the FSEvents path; this is the same guarantee for a direct read-then-write
/// like the checkbox toggle).
public enum ConflictGuard {
    /// `true` only if `url` was changed by something other than us since `snapshot`.
    /// Consults `Vault.wasSelfWrite`, which consumes the registry entry it checks — so
    /// calling this is a one-shot check per genuine disk change, same contract `Vault`
    /// already documents.
    public static func hasExternalChange(at url: URL, since snapshot: FileSnapshot, vault: Vault) -> Bool {
        guard let current = FileSnapshot.current(at: url), snapshot.differs(from: current) else {
            return false
        }
        return !vault.wasSelfWrite(path: url.path)
    }
}

/// Builds the sidecar path for a conflicting write: `<name>.conflict-<timestamp>.md`, in
/// the same directory as the original (never a subfolder) so it's visible right next to
/// the file it collided with.
public enum ConflictCopy {
    public static func url(for fileURL: URL, timestamp: Date) -> URL {
        let base = fileURL.deletingPathExtension().lastPathComponent
        let ext = fileURL.pathExtension
        let stamp = timestampFormatter.string(from: timestamp)
        let name = ext.isEmpty ? "\(base).conflict-\(stamp)" : "\(base).conflict-\(stamp).\(ext)"
        return fileURL.deletingLastPathComponent().appendingPathComponent(name)
    }

    /// Sortable and colon-free, so the sidecar name survives every volume format Loaf
    /// might land on.
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
