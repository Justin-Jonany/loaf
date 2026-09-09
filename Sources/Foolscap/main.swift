import AppKit
import WebKit
import FoolscapCore

// The `--dump-dashboard <vault> <output.html>` entry point renders the composed
// dashboard for `vault` to a standalone HTML file and exits — no GUI, no NSApplication
// run loop. It exists so the B1 screenshot proof (and any future tooling) can produce
// the exact HTML the app would show without driving the real window. Must run before
// AppKit is touched below.
if let flagIndex = CommandLine.arguments.firstIndex(of: "--dump-dashboard"),
   CommandLine.arguments.count > flagIndex + 2 {
    let vaultPath = CommandLine.arguments[flagIndex + 1]
    let outputPath = CommandLine.arguments[flagIndex + 2]
    let vault = Vault(root: URL(fileURLWithPath: vaultPath))
    let dashboard = DashboardComposer.compose(vault: vault)
    let body = DashboardRenderer.renderBody(dashboard)
    let html = HTMLPage.wrap(body: body, theme: Config.defaultTheme)
    do {
        try html.write(toFile: outputPath, atomically: true, encoding: .utf8)
        exit(0)
    } catch {
        FileHandle.standardError.write("Foolscap: couldn't write dashboard HTML: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

/// The body of `--demo-conflict-guard`, factored out so it reads top-to-bottom as the demo
/// script it is. Seeds a vault, simulates the morning run rewriting `tasks.md` while the
/// app has an in-flight checkbox toggle based on the version it originally read, runs the
/// real X1 guard logic (`ConflictGuard`/`ConflictDecision` from `FoolscapCore`), and prints
/// + leaves the resulting BEFORE/AFTER files under `dir` for inspection.
func runConflictGuardDemo(in dir: URL) throws {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let vault = Vault(root: dir)
    let tasksURL = dir.appendingPathComponent("tasks.md")

    let original = "- [ ] Email the landlord\n      @today · manual"
    try vault.writeAtomically(original, to: tasksURL)
    print("--- BEFORE: tasks.md, as the app read it ---")
    print(original)

    // The app's read — a checkbox toggle would base its in-flight write on this snapshot.
    let readSnapshot = FileSnapshot.current(at: tasksURL)!

    // Before that write lands, the morning run rewrites the file concurrently. Written
    // directly (bypassing Vault), exactly as a real external process would — never lands
    // in the self-write registry.
    let externalRewrite = original + "\n- [ ] Prep the deck\n      @2026-08-21 · calendar"
    try externalRewrite.write(to: tasksURL, atomically: true, encoding: .utf8)
    print("\n--- CONCURRENT WRITE: the morning run rewrites tasks.md on disk ---")
    print(externalRewrite)

    // Meanwhile the app has its own unsaved change in flight: the user ticked "Email the
    // landlord" based on the version it originally read, above.
    let dirtyBuffer = TaskBlock.toggling(
        original.components(separatedBy: "\n"), at: 0, checked: true, today: .today()
    )!.joined(separator: "\n")
    print("\n--- APP'S DIRTY BUFFER: the pending (unsaved) checkbox toggle ---")
    print(dirtyBuffer)

    let diskChanged = ConflictGuard.hasExternalChange(at: tasksURL, since: readSnapshot, vault: vault)
    let decision = ConflictDecision.decide(diskChangedSinceRead: diskChanged, bufferDirty: true)
    print("\n--- GUARD DECISION: diskChangedSinceRead=\(diskChanged), bufferDirty=true -> \(decision) ---")

    guard decision == .conflictKeepDiskSaveCopy else {
        print("Unexpected decision for this demo — nothing written.")
        return
    }

    let conflictURL = ConflictCopy.url(for: tasksURL, timestamp: Date())
    try vault.writeAtomically(dirtyBuffer, to: conflictURL)
    print(
        "\n--- NOTICE the user would see ---\n"
            + "tasks.md changed before your edit saved. Something else (likely the morning run) "
            + "rewrote tasks.md while you had an unsaved change. The on-disk version was kept; "
            + "your change was saved separately as \(conflictURL.lastPathComponent) so nothing was lost."
    )

    print("\n--- AFTER: on-disk tasks.md (kept, never overwritten by the app's write) ---")
    print(try vault.read(tasksURL))
    print("\n--- AFTER: \(conflictURL.lastPathComponent) (the app's saved-aside change) ---")
    print(try vault.read(conflictURL))
    print("\nVault directory listing:")
    for name in try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() {
        print("  \(name)")
    }
}

// The `--demo-conflict-guard <dir>` entry point is X1's non-GUI proof path (mirrors
// `--dump-dashboard` above): screencapture has no display to run against in a headless
// sandbox, so this drives the real guard logic against a real temp vault and leaves the
// BEFORE/AFTER files on disk as evidence instead. No GUI, no NSApplication run loop — must
// run before AppKit is touched below.
if let flagIndex = CommandLine.arguments.firstIndex(of: "--demo-conflict-guard"),
   CommandLine.arguments.count > flagIndex + 1 {
    let demoDir = URL(fileURLWithPath: CommandLine.arguments[flagIndex + 1])
    do {
        try runConflictGuardDemo(in: demoDir)
        exit(0)
    } catch {
        FileHandle.standardError.write("Foolscap: conflict-guard demo failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

// Wires the vault + renderer into the window: load config, bootstrap the vault, compose
// the dashboard from the three known files, render it, and repaint whenever one of them
// changes on disk. The panel is a composed dashboard, not a folder browser (DESIGN.md →
// "The panel").

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler {
    private var window: NoteWindow?
    private var statusItem: NSStatusItem?
    private var watcher: VaultWatcher?

    private var config = Config()
    private var vault: Vault!

    /// The three known files the dashboard composes from — nothing else. Matched by
    /// filename against watcher events so an unrelated vault edit doesn't trigger a
    /// repaint, and a stray file (`notes.md`, …) is never read at all.
    private static let dashboardFiles: Set<String> = ["brief.md", "tasks.md", "longterm.md"]

    func applicationDidFinishLaunching(_ notification: Notification) {
        config = Config.load()
        vault = Vault(root: Vault.resolveRoot(config: config))
        do {
            try vault.bootstrapIfEmpty()
        } catch {
            NSLog("Foolscap: couldn't bootstrap vault at \(vault.root.path): \(error)")
        }

        let window = NoteWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 486))
        window.installTaskToggleHandler(self)
        window.makeKeyAndOrderFront(nil)
        self.window = window

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "◳"
        item.menu = buildMenu()
        self.statusItem = item

        renderDashboard()
        startWatching()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Notes", action: #selector(toggle), keyEquivalent: "n"))
        menu.addItem(NSMenuItem(title: "Open Vault in Finder", action: #selector(openVaultInFinder), keyEquivalent: "o"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Foolscap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        // Quit's target stays nil so terminate: routes down the responder chain to NSApp, which implements it.
        menu.items.forEach { item in
            item.target = (item.action == #selector(NSApplication.terminate(_:))) ? nil : self
        }
        return menu
    }

    @objc private func toggle() {
        guard let window else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func openVaultInFinder() {
        NSWorkspace.shared.open(vault.root)
    }

    // MARK: - Dashboard composition + rendering

    /// Reads exactly `brief.md`/`tasks.md`/`longterm.md` (`DashboardComposer`), buckets
    /// their tasks, and renders the four sections. No folder browser, no file picker.
    private func renderDashboard() {
        let dashboard = DashboardComposer.compose(vault: vault, today: .today())
        let body = DashboardRenderer.renderBody(dashboard)
        window?.load(html: HTMLPage.wrap(body: body, theme: config.theme), baseURL: vault.root)
    }

    // MARK: - Checkbox write-back

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "toggleTask" else { return }
        guard let body = message.body as? [String: Any],
              let file = body["file"] as? String,
              let line = (body["line"] as? NSNumber)?.intValue,
              let checked = (body["checked"] as? NSNumber)?.boolValue
        else { return }
        toggleTask(file: file, atLine: line, checked: checked)
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

        saveSharedFile(updatedLines.joined(separator: "\n"), to: noteURL, readSnapshot: readSnapshot)
        // Whether the write went through, got saved as a conflict copy, or (in principle)
        // reloaded clean, re-render so the panel reflects whatever is now the truth on disk.
        renderDashboard()
    }

    /// X1's write-conflict guard (ROADMAP.md → Cross-cutting), applied to a pending change
    /// to a shared file before it lands. `bufferDirty` is always `true` here — the caller
    /// only reaches this with a toggle it wants written — so `.reloadClean` can't come back
    /// from this call site; that case is what `startWatching`'s plain repaint already
    /// handles when disk changes with nothing of ours pending.
    private func saveSharedFile(_ dirtyContent: String, to url: URL, readSnapshot: FileSnapshot) {
        let diskChanged = ConflictGuard.hasExternalChange(at: url, since: readSnapshot, vault: vault)
        switch ConflictDecision.decide(diskChangedSinceRead: diskChanged, bufferDirty: true) {
        case .writeThrough:
            do {
                try vault.writeAtomically(dirtyContent, to: url)
            } catch {
                NSLog("Foolscap: couldn't write \(url.path): \(error)")
            }
        case .conflictKeepDiskSaveCopy:
            // Last-write-wins would silently destroy whichever side loses the race
            // (ROADMAP.md → Hazards → "Write conflicts on shared files"). Keep the on-disk
            // version untouched and stash the app's version next to it instead.
            let conflictURL = ConflictCopy.url(for: url, timestamp: Date())
            do {
                try vault.writeAtomically(dirtyContent, to: conflictURL)
                NSLog(
                    "Foolscap: write conflict on \(url.lastPathComponent) — kept the on-disk "
                        + "version, saved your change to \(conflictURL.lastPathComponent)"
                )
                presentConflictNotice(originalFile: url.lastPathComponent, conflictFile: conflictURL.lastPathComponent)
            } catch {
                NSLog("Foolscap: couldn't save conflict copy for \(url.path): \(error)")
            }
        case .reloadClean:
            break
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

    private func startWatching() {
        let watcher = VaultWatcher(vault: vault) { [weak self] changedPaths in
            guard let self else { return }
            guard changedPaths.contains(where: { Self.dashboardFiles.contains($0.lastPathComponent) }) else { return }
            DispatchQueue.main.async {
                self.renderDashboard()
            }
        }
        watcher.start()
        self.watcher = watcher
    }
}

let app = NSApplication.shared
// Ordinary app: shows in the Dock and Cmd+Tab, like any normal document window.
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
