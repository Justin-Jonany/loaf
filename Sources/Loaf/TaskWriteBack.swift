import AppKit
import WebKit
import LoafCore

extension AppDelegate {
    // MARK: - Checkbox write-back

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "toggleTask":
            guard let body = message.body as? [String: Any],
                  let file = body["file"] as? String,
                  let line = (body["line"] as? NSNumber)?.intValue,
                  let checked = (body["checked"] as? NSNumber)?.boolValue
            else { return }
            toggleTask(file: file, atLine: line, checked: checked)
        case "focusTask":
            guard let body = message.body as? [String: Any],
                  let file = body["file"] as? String,
                  let line = (body["line"] as? NSNumber)?.intValue,
                  let focus = (body["focus"] as? NSNumber)?.boolValue
            else { return }
            setFocus(file: file, atLine: line, focus: focus)
        case "reorderTask":
            guard let body = message.body as? [String: Any],
                  let file = body["file"] as? String,
                  let line = (body["line"] as? NSNumber)?.intValue,
                  let beforeLine = (body["beforeLine"] as? NSNumber)?.intValue
            else { return }
            reorderTask(file: file, fromLine: line, beforeLine: beforeLine)
        case "archiveTask":
            guard let body = message.body as? [String: Any],
                  let file = body["file"] as? String,
                  let line = (body["line"] as? NSNumber)?.intValue
            else { return }
            archiveTask(file: file, atLine: line)
        case "restoreTask":
            guard let body = message.body as? [String: Any],
                  let file = body["file"] as? String,
                  let line = (body["line"] as? NSNumber)?.intValue
            else { return }
            restoreTask(archiveFile: file, atLine: line)
        case "showDashboard":
            renderDashboard()
        default:
            return
        }
    }

    /// A4's write-back, adapted to the dashboard: the click carries `data-file` (one of the
    /// three known files — see `DashboardRenderer`) alongside its line, so we know which
    /// note to write. Re-reads that note fresh from disk (never the DOM's stale copy),
    /// validates that `line` still starts a task block — the file may have changed
    /// underneath the click — and either applies the toggle or, if the line no longer
    /// matches, drops the click and re-renders so the panel reflects current truth. Writes
    /// through `TaskBlock.toggling` (the metadata-below format — see DESIGN.md → Tasks), so
    /// `✓done` lands on the metadata line, never the task line.
    private func toggleTask(file: String, atLine line: Int, checked: Bool) {
        guard Self.dashboardFiles.contains(file) else { return }
        let noteURL = vault.root.appendingPathComponent(file)
        guard let markdown = try? vault.read(noteURL) else { return }
        // Snapshot the file as we found it — the version the toggle below is based on —
        // so the X1 guard can tell whether the morning run (or anything else) rewrote it
        // out from under this click before the write below lands.
        guard let readSnapshot = FileSnapshot.current(at: noteURL) else { return }
        let lines = markdown.components(separatedBy: "\n")

        guard line >= 1, line <= lines.count,
              let updatedLines = TaskBlock.toggling(lines, at: line - 1, checked: checked)
        else {
            renderDashboard()
            return
        }

        if !saveSharedFile(updatedLines.joined(separator: "\n"), to: noteURL, readSnapshot: readSnapshot) {
            NSLog("Loaf: checkbox toggle for \(file) line \(line) did not land — see the write/conflict log above")
        }
        // Whether the write went through, got saved as a conflict copy, or (in principle)
        // reloaded clean, re-render so the panel reflects whatever is now the truth on disk.
        renderDashboard()
    }

    /// B7's write-back for the per-row `★` focus toggle, mirroring `toggleTask` exactly:
    /// re-reads the note fresh from disk, validates that `line` still starts a task block,
    /// and either applies the flag or drops a stale click and re-renders. Writes through
    /// `TaskBlock.settingFocus` (the metadata-below format — see DESIGN.md → Tasks), so `★`
    /// lands on the metadata line and `@due` is left untouched either way.
    private func setFocus(file: String, atLine line: Int, focus: Bool) {
        guard Self.dashboardFiles.contains(file) else { return }
        let noteURL = vault.root.appendingPathComponent(file)
        guard let markdown = try? vault.read(noteURL) else { return }
        // Snapshot the file as we found it — the version the toggle below is based on —
        // so the X1 guard can tell whether the morning run (or anything else) rewrote it
        // out from under this click before the write below lands.
        guard let readSnapshot = FileSnapshot.current(at: noteURL) else { return }
        let lines = markdown.components(separatedBy: "\n")

        guard line >= 1, line <= lines.count,
              let updatedLines = TaskBlock.settingFocus(lines, at: line - 1, focus: focus)
        else {
            renderDashboard()
            return
        }

        if !saveSharedFile(updatedLines.joined(separator: "\n"), to: noteURL, readSnapshot: readSnapshot) {
            NSLog("Loaf: focus toggle for \(file) line \(line) did not land — see the write/conflict log above")
        }
        // Whether the write went through, got saved as a conflict copy, or (in principle)
        // reloaded clean, re-render so the panel reflects whatever is now the truth on disk.
        renderDashboard()
    }

    /// The write-back for Today's drag-to-reorder (DECISIONS.md 2026-09-14), mirroring
    /// `toggleTask`/`setFocus` exactly: re-reads the note fresh from disk, validates that
    /// `fromLine` still starts a task block, and either applies the move or drops a
    /// stale/no-op drag and re-renders. `beforeLine <= 0` means "move to the end of the
    /// file" (the DOM has no row to name there), translated to `lines.count` for
    /// `TaskBlock.moving`. Writes through `TaskBlock.moving`, which moves the block's lines
    /// verbatim — a reorder must never reformat the task.
    private func reorderTask(file: String, fromLine: Int, beforeLine: Int) {
        guard Self.dashboardFiles.contains(file) else { return }
        let noteURL = vault.root.appendingPathComponent(file)
        guard let markdown = try? vault.read(noteURL) else { return }
        // Snapshot the file as we found it — the version the move below is based on —
        // so the X1 guard can tell whether the morning run (or anything else) rewrote it
        // out from under this drag before the write below lands.
        guard let readSnapshot = FileSnapshot.current(at: noteURL) else { return }
        let lines = markdown.components(separatedBy: "\n")
        let target = beforeLine <= 0 ? lines.count : beforeLine - 1

        guard fromLine >= 1, fromLine <= lines.count,
              let updatedLines = TaskBlock.moving(lines, blockAt: fromLine - 1, toBefore: target)
        else {
            renderDashboard()
            return
        }

        if !saveSharedFile(updatedLines.joined(separator: "\n"), to: noteURL, readSnapshot: readSnapshot) {
            NSLog("Loaf: reorder for \(file) line \(fromLine) did not land — see the write/conflict log above")
        }
        // Whether the write went through, got saved as a conflict copy, or (in principle)
        // reloaded clean, re-render so the panel reflects whatever is now the truth on disk.
        renderDashboard()
    }

    /// The permanent-archive write-back for the panel's "Archive" button on a completed
    /// task (DECISIONS.md 2026-09-11). Mirrors `toggleTask`/`setFocus`'s
    /// read-snapshot-mutate-write shape, but as a TWO-file write: the archive shard is
    /// written FIRST, and `file` is only stripped of the block SECOND, once the shard
    /// write actually lands (now observable via `saveSharedFile`'s `Bool` return — the
    /// step-0 fix) — so a crash between the two writes leaves a recoverable duplicate on
    /// disk, never a loss. Both writes are routed through the same conflict-guarded
    /// `saveSharedFile` the existing mutators use.
    private func archiveTask(file: String, atLine line: Int) {
        guard Self.dashboardFiles.contains(file) else { return }
        let noteURL = vault.root.appendingPathComponent(file)
        guard let markdown = try? vault.read(noteURL) else { return }
        guard let readSnapshot = FileSnapshot.current(at: noteURL) else { return }
        let lines = markdown.components(separatedBy: "\n")

        let archivedAt = Date()
        guard line >= 1, line <= lines.count,
              let (archivedBlockText, remainingLines) = TaskBlock.archiving(lines, at: line - 1, archivedAt: archivedAt)
        else {
            renderDashboard()
            return
        }

        let archiveURL = Archive.archiveShardURL(for: archivedAt, vault: vault)
        let existingShard = (try? vault.read(archiveURL)) ?? ""
        let updatedShard = existingShard.isEmpty ? archivedBlockText : existingShard + "\n" + archivedBlockText
        // The shard commonly doesn't exist yet (first archive of the month) — a sentinel
        // snapshot that can never match a real file makes ConflictGuard treat "someone
        // created it since we looked" as an external change, same as an edited file.
        let archiveSnapshot = FileSnapshot.current(at: archiveURL) ?? FileSnapshot(mtime: .distantPast, size: -1)

        guard saveSharedFile(updatedShard, to: archiveURL, readSnapshot: archiveSnapshot) else {
            NSLog("Loaf: couldn't append the archived task to \(archiveURL.lastPathComponent) — leaving \(file) untouched so nothing is lost")
            renderDashboard()
            return
        }

        if !saveSharedFile(remainingLines.joined(separator: "\n"), to: noteURL, readSnapshot: readSnapshot) {
            NSLog("Loaf: the block landed in \(archiveURL.lastPathComponent) but the strip from \(file) did not — it's now duplicated on disk (recoverable), not lost")
        }
        renderDashboard()
    }

    /// The inverse of `archiveTask`, driven by the archive viewer's per-row "Restore"
    /// button. `TaskBlock.restoring` reopens the task (clears `isDone`/`done`/
    /// `archivedAt` — DECISIONS.md 2026-09-11, "restore reopens the task"). The symmetric
    /// mirror of `archiveTask`'s write order: `tasks.md` gets the restored block FIRST,
    /// the archive shard is stripped SECOND, so a crash between the two again leaves a
    /// recoverable duplicate rather than a loss.
    private func restoreTask(archiveFile: String, atLine line: Int) {
        guard Self.isArchiveShardPath(archiveFile) else { return }
        let archiveURL = vault.root.appendingPathComponent(archiveFile)
        guard let markdown = try? vault.read(archiveURL) else { return }
        guard let readSnapshot = FileSnapshot.current(at: archiveURL) else { return }
        let lines = markdown.components(separatedBy: "\n")

        guard line >= 1, line <= lines.count,
              let (restoredBlockText, remainingLines) = TaskBlock.restoring(lines, at: line - 1)
        else {
            renderArchiveView()
            return
        }

        let tasksURL = vault.root.appendingPathComponent("tasks.md")
        let existingTasks = (try? vault.read(tasksURL)) ?? ""
        let updatedTasks = existingTasks.isEmpty ? restoredBlockText : existingTasks + "\n" + restoredBlockText
        let tasksSnapshot = FileSnapshot.current(at: tasksURL) ?? FileSnapshot(mtime: .distantPast, size: -1)

        guard saveSharedFile(updatedTasks, to: tasksURL, readSnapshot: tasksSnapshot) else {
            NSLog("Loaf: couldn't append the restored task to tasks.md — leaving \(archiveFile) untouched so nothing is lost")
            renderArchiveView()
            return
        }

        if !saveSharedFile(remainingLines.joined(separator: "\n"), to: archiveURL, readSnapshot: readSnapshot) {
            NSLog("Loaf: the block landed in tasks.md but the strip from \(archiveFile) did not — it's now duplicated on disk (recoverable), not lost")
        }
        renderArchiveView()
    }

    /// Guards a `restoreTask` message payload the same way `dashboardFiles` guards the
    /// other handlers — never trust a path straight off a `WKScriptMessage`. Only the
    /// current month's shard is ever rendered with a restore button, but this holds for
    /// any past shard too, since a restore from an older month is a legitimate action.
    private static func isArchiveShardPath(_ file: String) -> Bool {
        file.hasPrefix("archive/") && file.hasSuffix(".md")
    }

    /// X1's write-conflict guard (ROADMAP.md → Cross-cutting), applied to a pending change
    /// to a shared file before it lands. `bufferDirty` is always `true` here — the caller
    /// only reaches this with a toggle it wants written — so `.reloadClean` can't come back
    /// from this call site; that case is what `startWatching`'s plain repaint already
    /// handles when disk changes with nothing of ours pending.
    ///
    /// Returns whether `dirtyContent` actually landed AT `url` — `false` on a thrown write
    /// error or a caught conflict (the on-disk version was kept and the app's change saved
    /// aside instead). Previously this swallowed a write failure (logged and returned
    /// `Void`), so a caller had no way to tell success from failure — a latent data-safety
    /// bug on its own, and the reason the archive's two-file write below couldn't safely
    /// decide whether to strip the source file after the shard write.
    @discardableResult
    private func saveSharedFile(_ dirtyContent: String, to url: URL, readSnapshot: FileSnapshot) -> Bool {
        let diskChanged = ConflictGuard.hasExternalChange(at: url, since: readSnapshot, vault: vault)
        switch ConflictDecision.decide(diskChangedSinceRead: diskChanged, bufferDirty: true) {
        case .writeThrough:
            do {
                try vault.writeAtomically(dirtyContent, to: url)
                return true
            } catch {
                NSLog("Loaf: couldn't write \(url.path): \(error)")
                return false
            }
        case .conflictKeepDiskSaveCopy:
            // Last-write-wins would silently destroy whichever side loses the race
            // (ROADMAP.md → Hazards → "Write conflicts on shared files"). Keep the on-disk
            // version untouched and stash the app's version next to it instead.
            let conflictURL = ConflictCopy.url(for: url, timestamp: Date())
            do {
                try vault.writeAtomically(dirtyContent, to: conflictURL)
                NSLog(
                    "Loaf: write conflict on \(url.lastPathComponent) — kept the on-disk "
                        + "version, saved your change to \(conflictURL.lastPathComponent)"
                )
                presentConflictNotice(originalFile: url.lastPathComponent, conflictFile: conflictURL.lastPathComponent)
            } catch {
                NSLog("Loaf: couldn't save conflict copy for \(url.path): \(error)")
            }
            return false
        case .reloadClean:
            return false
        }
    }

    /// Tells the user their change didn't land because the file changed under it. A modal
    /// alert rather than a background notification: D2 owns the richer decision/failure
    /// notification surface (ROADMAP.md → Wave 3), and a write conflict is rare enough
    /// that a blocking dialog at the moment it happens is preferable to a silent toast that
    /// could go unnoticed.
    private func presentConflictNotice(originalFile: String, conflictFile: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(originalFile) changed before your edit saved"
        alert.informativeText =
            "Something else (likely the morning run) rewrote \(originalFile) while you had an "
            + "unsaved change. The on-disk version was kept; your change was saved separately "
            + "as \(conflictFile) so nothing was lost."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
