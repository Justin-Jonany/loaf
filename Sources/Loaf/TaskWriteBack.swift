import AppKit
import WebKit
import LoafCore

extension AppDelegate {
    // MARK: - Task write-back

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "showDashboard" {
            renderDashboard()
            return
        }
        guard let body = message.body as? [String: Any],
              let file = body["file"] as? String,
              let line = (body["line"] as? NSNumber)?.intValue
        else { return }

        switch message.name {
        case "toggleTask":
            guard let checked = (body["checked"] as? NSNumber)?.boolValue else { return }
            // `TaskBlock.toggling` stamps `✓done` on the metadata line, never the task line.
            rewriteDashboardFile(file, line: line, action: "checkbox toggle") {
                TaskBlock.toggling($0, at: line - 1, checked: checked)
            }
        case "focusTask":
            guard let focus = (body["focus"] as? NSNumber)?.boolValue else { return }
            rewriteDashboardFile(file, line: line, action: "focus toggle") {
                TaskBlock.settingFocus($0, at: line - 1, focus: focus)
            }
        case "reorderTask":
            guard let beforeLine = (body["beforeLine"] as? NSNumber)?.intValue else { return }
            // `beforeLine <= 0` means "move to the end": the DOM has no row to name there.
            // `TaskBlock.moving` moves the block's lines verbatim; a reorder never reformats.
            rewriteDashboardFile(file, line: line, action: "reorder") { lines in
                TaskBlock.moving(lines, blockAt: line - 1, toBefore: beforeLine <= 0 ? lines.count : beforeLine - 1)
            }
        case "archiveTask":
            archiveTask(file: file, atLine: line)
        case "restoreTask":
            restoreTask(archiveFile: file, atLine: line)
        default:
            return
        }
    }

    /// Applies a single-file edit from a panel click. Re-reads `file` fresh from disk rather
    /// than trusting the DOM's copy, because the file may have changed underneath the click.
    /// `transform` gets the current lines and returns `nil` when the clicked `line` (1-based)
    /// no longer starts a task block; that stale click is dropped. Either way the dashboard
    /// re-renders, so the panel always shows what's actually on disk.
    private func rewriteDashboardFile(
        _ file: String, line: Int, action: String, _ transform: ([String]) -> [String]?
    ) {
        guard Self.dashboardFiles.contains(file) else { return }
        let noteURL = vault.root.appendingPathComponent(file)
        // The snapshot is the version this edit is based on, so the conflict guard can tell
        // whether the morning run rewrote the file before our write lands.
        guard let markdown = try? vault.read(noteURL),
              let readSnapshot = FileSnapshot.current(at: noteURL)
        else { return }
        defer { renderDashboard() }

        let lines = markdown.components(separatedBy: "\n")
        guard line >= 1, line <= lines.count, let updatedLines = transform(lines) else { return }

        if !saveSharedFile(updatedLines.joined(separator: "\n"), to: noteURL, readSnapshot: readSnapshot) {
            NSLog("Loaf: \(action) for \(file) line \(line) did not land — see the write/conflict log above")
        }
    }

    /// Appends `blockText` to `url` through the conflict guard, creating the file if it
    /// doesn't exist. Returns whether the write landed.
    private func appendBlock(_ blockText: String, to url: URL) -> Bool {
        let existing = (try? vault.read(url)) ?? ""
        let updated = existing.isEmpty ? blockText : existing + "\n" + blockText
        // The file often doesn't exist yet (e.g. the first archive of the month). A sentinel
        // snapshot that can never match a real file makes the guard treat "someone created it
        // since we looked" as an external change, same as an edited file.
        let snapshot = FileSnapshot.current(at: url) ?? FileSnapshot(mtime: .distantPast, size: -1)
        return saveSharedFile(updated, to: url, readSnapshot: snapshot)
    }

    /// Moves a task into this month's archive shard (DECISIONS.md 2026-09-11). A two-file
    /// write, ordered so a crash between them leaves a recoverable duplicate, never a loss:
    /// the shard is written first, and `file` is stripped only once that write has landed.
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
        guard appendBlock(archivedBlockText, to: archiveURL) else {
            NSLog("Loaf: couldn't append the archived task to \(archiveURL.lastPathComponent) — leaving \(file) untouched so nothing is lost")
            renderDashboard()
            return
        }

        if !saveSharedFile(remainingLines.joined(separator: "\n"), to: noteURL, readSnapshot: readSnapshot) {
            NSLog("Loaf: the block landed in \(archiveURL.lastPathComponent) but the strip from \(file) did not — it's now duplicated on disk (recoverable), not lost")
        }
        renderDashboard()
    }

    /// The inverse of `archiveTask`, from the archive viewer's "Restore" button. Restoring
    /// also reopens the task (DECISIONS.md 2026-09-11). Same crash-safe order, mirrored:
    /// `tasks.md` gets the block first, and the shard is stripped only once that has landed.
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

        guard appendBlock(restoredBlockText, to: vault.root.appendingPathComponent("tasks.md")) else {
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

    /// Writes a change to a shared file through the write-conflict guard. If something else
    /// (usually the morning run) changed the file since we read it, the on-disk version is
    /// kept and our change is saved aside as a conflict copy. `bufferDirty` is always `true`
    /// here, so `.reloadClean` can't come back; the watcher's plain repaint covers that case.
    ///
    /// Returns whether `dirtyContent` actually landed at `url`. The two-file archive/restore
    /// writes depend on this to decide whether it's safe to strip the source.
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
    /// alert rather than a notification: a conflict is rare, and a silent toast could go
    /// unnoticed.
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
