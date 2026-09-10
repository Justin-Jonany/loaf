import AppKit
import WebKit
import UserNotifications
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
    // Matches `DashboardComposer.compose`'s own default (`.today()`, not the 6am-rollover
    // `.effectiveToday()` the real app uses) — this dump is a standalone snapshot tool, so
    // composing and rendering must agree on the same "today" the composer already used.
    let today = CalendarDate.today()
    let dashboard = DashboardComposer.compose(vault: vault, today: today)
    let body = DashboardRenderer.renderBody(dashboard, today: today)
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

/// The vault-root sidecar the morning routine writes when today needs a decision or a run
/// failed (ROADMAP.md → D2; DECISIONS.md 2026-08-23). A dotfile, so `VaultWatcher`'s `.md`
/// filter still catches changes to it while `Vault.notePaths()` skips it as a note.
let routineSignalFileName = ".routine-signal.md"

let routineDecisionTitle = "Foolscap needs a decision"
/// Distinct from the decision title — a broken/failed run must read as louder, not as an
/// ordinary nudge (DESIGN.md → Trust: "Failure is loud").
let routineFailureTitle = "⚠️ Foolscap run failed"

/// The notification body for a decision nudge: the one-line reason, plus each question as
/// its own bullet. The actual back-and-forth happens in a Claude Code chat, not the panel
/// (DESIGN.md → "The daily loop") — this is just the nudge to go there.
func routineDecisionBody(reason: String, questions: [String]) -> String {
    guard !questions.isEmpty else { return reason }
    return ([reason] + questions.map { "• \($0)" }).joined(separator: "\n")
}

/// The body of `--demo-signal`, factored out so it reads top-to-bottom as the demo script
/// it is. Reads `.routine-signal.md` from `vaultPath` (if present at all) through the real
/// `RoutineSignal.parse`/`SignalNudge.decide` logic from `FoolscapCore` and prints which
/// nudge it would fire — title/body — without touching `UNUserNotificationCenter` or
/// AppKit. This is D2's non-GUI proof path (mirrors `--demo-conflict-guard` above): the
/// sandbox has no display to capture a real notification banner in.
func runSignalDemo(vaultPath: String) throws {
    let vault = Vault(root: URL(fileURLWithPath: vaultPath))
    let signalURL = vault.root.appendingPathComponent(routineSignalFileName)
    let text = (try? vault.read(signalURL)) ?? ""
    let signal = RoutineSignal.parse(text)
    let nudge = SignalNudge.decide(for: signal)

    print("--- \(signalURL.path) ---")
    print(text.isEmpty ? "(absent — no signal file)" : text)

    print("\n--- PARSED ---")
    if let signal {
        print("status: \(signal.status.rawValue), reason: \"\(signal.reason)\", questions: \(signal.questions)")
    } else {
        print("nil — clear day")
    }

    print("\n--- NUDGE ---")
    switch nudge {
    case .none:
        print("none — silent, no notification posted")
    case .decision(let reason, let questions):
        print("title: \(routineDecisionTitle)")
        print("body:  \(routineDecisionBody(reason: reason, questions: questions))")
    case .failure(let reason):
        print("title: \(routineFailureTitle)")
        print("body:  \(reason)")
    }
}

// The `--demo-signal <vault>` entry point, D2's non-GUI proof path (mirrors
// `--demo-conflict-guard` above) — must run before AppKit is touched below.
if let flagIndex = CommandLine.arguments.firstIndex(of: "--demo-signal"),
   CommandLine.arguments.count > flagIndex + 1 {
    let demoVaultPath = CommandLine.arguments[flagIndex + 1]
    do {
        try runSignalDemo(vaultPath: demoVaultPath)
        exit(0)
    } catch {
        FileHandle.standardError.write("Foolscap: signal demo failed: \(error)\n".data(using: .utf8)!)
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

        requestNotificationAuthorization()
        renderDashboard()
        checkRoutineSignal()
        startWatching()
        startObservingDayChange()
        applyAccessibilityDisplayOptions()
        startObservingAccessibilityDisplayOptions()
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
    ///
    /// Buckets against `CalendarDate.effectiveToday()`, not `.today()` — the dashboard's
    /// "today" rolls over at 6am local, not midnight (DESIGN.md → "The daily loop").
    private func renderDashboard() {
        let today = CalendarDate.effectiveToday()
        let dashboard = DashboardComposer.compose(vault: vault, today: today)
        let body = DashboardRenderer.renderBody(dashboard, today: today)
        window?.load(html: HTMLPage.wrap(body: body, theme: config.theme), baseURL: vault.root)
    }

    // MARK: - Recompute on wake / day change

    /// The dashboard's bucketing depends on the effective day, so it must recompute
    /// whenever that day could have changed — and *only* then. Deliberately not a timer:
    /// the run only fires on wake or an actual calendar day change (ROADMAP B5), so a
    /// sleeping Mac doesn't burn cycles polling a clock that isn't moving for it anyway.
    /// `NSCalendarDayChangedNotification` catches the midnight-while-awake case;
    /// `NSWorkspace.didWakeNotification` catches "missed 6am asleep, catches up on wake"
    /// (DESIGN.md → "The daily loop").
    private func startObservingDayChange() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(recomputeOnSystemNotification),
            name: NSWorkspace.didWakeNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(recomputeOnSystemNotification),
            name: NSNotification.Name.NSCalendarDayChanged, object: nil
        )
    }

    @objc private func recomputeOnSystemNotification() {
        renderDashboard()
    }

    // MARK: - Accessibility display options (ROADMAP X2 — Accessibility pass)

    /// Reduce Transparency has no CSS-only fix — only Swift can turn off the native
    /// `NSVisualEffectView` vibrancy — so this reads the current system setting and pushes
    /// it into the window. Increase Contrast doesn't need a Swift-side push: WebKit already
    /// feeds `prefers-contrast` into the page from the same system setting, so
    /// `frosted.css`'s `@media (prefers-contrast: more)` reacts on its own.
    private func applyAccessibilityDisplayOptions() {
        window?.applyReduceTransparency(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
    }

    /// Reduce Transparency can be toggled while the app is running (System Settings >
    /// Accessibility > Display), so the window must react live, not just at launch.
    private func startObservingAccessibilityDisplayOptions() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(accessibilityDisplayOptionsDidChange),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil
        )
    }

    @objc private func accessibilityDisplayOptionsDidChange() {
        applyAccessibilityDisplayOptions()
    }

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

        saveSharedFile(updatedLines.joined(separator: "\n"), to: noteURL, readSnapshot: readSnapshot)
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
            let changedNames = Set(changedPaths.map { $0.lastPathComponent })

            if changedNames.contains(routineSignalFileName) {
                DispatchQueue.main.async {
                    self.checkRoutineSignal()
                }
            }
            guard changedNames.contains(where: { Self.dashboardFiles.contains($0) }) else { return }
            DispatchQueue.main.async {
                self.renderDashboard()
            }
        }
        watcher.start()
        self.watcher = watcher
    }

    // MARK: - Decision / failure notification (ticket D2)

    /// Asks macOS for permission to post user notifications. Fired once at launch; if the
    /// user has already answered (or denied) this is a no-op beyond the one system call.
    /// Silent about the outcome beyond logging — nothing downstream needs to branch on it:
    /// a denied request just means `add(_:)` below quietly does nothing, same as any other
    /// notification-disabled app.
    private func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                NSLog("Foolscap: notification authorization request failed: \(error)")
            }
        }
    }

    /// Reads `.routine-signal.md` fresh from disk and posts the nudge it maps to (or
    /// nothing, on a clear day) — called once at launch and again whenever the watcher
    /// reports the signal file changed. All the actual decision logic
    /// (`RoutineSignal.parse` / `SignalNudge.decide`) lives in `FoolscapCore`, pure and
    /// unit-tested; this is just the AppKit-side wiring DESIGN.md's boundary keeps out of
    /// `FoolscapCore`.
    private func checkRoutineSignal() {
        let signalURL = vault.root.appendingPathComponent(routineSignalFileName)
        // An unreadable-but-present file (permissions, non-UTF8 content, ...) collapses to
        // the same "" as a genuinely absent one; `RoutineSignal.parse("")` is `nil` either
        // way, so both read as the clear-day state rather than a spurious failure nudge.
        let text = (try? vault.read(signalURL)) ?? ""
        postNudge(SignalNudge.decide(for: RoutineSignal.parse(text)))
    }

    private func postNudge(_ nudge: SignalNudge) {
        switch nudge {
        case .none:
            break // Silent on a clear day (DESIGN.md → Trust) — no notification at all.
        case .decision(let reason, let questions):
            postNotification(
                title: routineDecisionTitle,
                body: routineDecisionBody(reason: reason, questions: questions),
                interruptionLevel: .active,
                sound: .default
            )
        case .failure(let reason):
            // Distinct from the decision nudge, not just a different string: a
            // time-sensitive interruption level (can pierce Focus filtering that would
            // hold back an ordinary notification) plus the critical sound — DESIGN.md →
            // Trust: "Failure is loud," so a failed/broken run must not read as an
            // ordinary nudge, let alone stay silent like a clear day.
            postNotification(
                title: routineFailureTitle,
                body: reason,
                interruptionLevel: .timeSensitive,
                sound: .defaultCritical
            )
        }
    }

    private func postNotification(
        title: String, body: String, interruptionLevel: UNNotificationInterruptionLevel, sound: UNNotificationSound
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound
        content.interruptionLevel = interruptionLevel

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("Foolscap: couldn't post notification \"\(title)\": \(error)")
            }
        }
    }
}

let app = NSApplication.shared
// Ordinary app: shows in the Dock and Cmd+Tab, like any normal document window.
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
