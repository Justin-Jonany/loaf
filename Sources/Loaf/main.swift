import AppKit
import WebKit
import UserNotifications
import LoafCore

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
    // Reads the real config's theme (same default path the app itself loads) rather than
    // the hardcoded default — now that the live app re-reads `theme` on every repaint
    // (live theme switching, DECISIONS.md 2026-09-11), this dump tool would otherwise
    // silently stop matching "the exact HTML the app would show" for a non-default theme.
    let html = HTMLPage.wrap(body: body, theme: Config.load().theme)
    do {
        try html.write(toFile: outputPath, atomically: true, encoding: .utf8)
        exit(0)
    } catch {
        FileHandle.standardError.write("Loaf: couldn't write dashboard HTML: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

/// The body of `--demo-conflict-guard`, factored out so it reads top-to-bottom as the demo
/// script it is. Seeds a vault, simulates the morning run rewriting `tasks.md` while the
/// app has an in-flight checkbox toggle based on the version it originally read, runs the
/// real X1 guard logic (`ConflictGuard`/`ConflictDecision` from `LoafCore`), and prints
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
        FileHandle.standardError.write("Loaf: conflict-guard demo failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

/// The body of `--demo-archive`, factored out so it reads top-to-bottom as the demo
/// script it is (mirrors `runConflictGuardDemo` above). Seeds a vault with one open and
/// one already-completed task, archives the completed one — exercising the same
/// archive-shard-first-then-strip write ORDER `archiveTask` uses in the real app
/// (DECISIONS.md 2026-09-11: a crash between the two writes must leave a recoverable
/// duplicate, never a loss) — then restores it back, the symmetric mirror. Also archives
/// the still-open task (DECISIONS.md 2026-09-11, widened: archiving is no longer gated
/// on done), proving that path lands in the shard with no `✓done` rather than a done
/// task's `✓done` surviving unchanged. Prints `tasks.md`/the archive shard at each step
/// so the two-file write and its ordering are inspectable without a GUI.
func runArchiveDemo(in dir: URL) throws {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let vault = Vault(root: dir)
    let tasksURL = dir.appendingPathComponent("tasks.md")

    let original = """
    - [ ] Email the landlord
          @today · manual
    - [x] Prep the client deck
          @2026-08-20 · calendar · !high · #schoolwork · ✓2026-08-20
    """
    try vault.writeAtomically(original, to: tasksURL)
    print("--- BEFORE: tasks.md ---")
    print(original)

    // The done task is the second block, starting at (0-based) line index 2.
    let archivedAt = Date()
    guard let (archivedBlockText, remainingLines) = TaskBlock.archiving(
        original.components(separatedBy: "\n"), at: 2, archivedAt: archivedAt
    ) else {
        print("Unexpected: line 2 isn't an archivable checkbox — nothing written.")
        return
    }

    let archiveURL = Archive.archiveShardURL(for: archivedAt, vault: vault)

    // STEP 1: the archive shard is written FIRST.
    try vault.writeAtomically(archivedBlockText, to: archiveURL)
    print("\n--- STEP 1: archive shard written first (\(archiveURL.lastPathComponent)) ---")
    print(try vault.read(archiveURL))

    // STEP 2: tasks.md is only stripped once step 1 has actually landed.
    try vault.writeAtomically(remainingLines.joined(separator: "\n"), to: tasksURL)
    print("\n--- STEP 2: tasks.md stripped of the archived block ---")
    print(try vault.read(tasksURL))

    // STEP 2b: archive the still-OPEN task too (DECISIONS.md 2026-09-11, widened —
    // archiving is no longer gated on done). Same shard-first-then-strip order as above;
    // the point of this step is what the archived block DOESN'T carry — no ✓done.
    guard let (openArchivedText, afterOpenArchive) = TaskBlock.archiving(
        remainingLines, at: 0, archivedAt: archivedAt
    ) else {
        print("Unexpected: the open task isn't an archivable checkbox — nothing written.")
        return
    }
    let shardWithBoth = try vault.read(archiveURL) + "\n" + openArchivedText
    try vault.writeAtomically(shardWithBoth, to: archiveURL)
    try vault.writeAtomically(afterOpenArchive.joined(separator: "\n"), to: tasksURL)
    print("\n--- STEP 2b: the still-open task archived too, with no ✓done ---")
    print(try vault.read(archiveURL))
    let openArchivedParsed = TaskBlock.parse(openArchivedText, today: .today())!
    print(
        "isDone: \(openArchivedParsed.isDone), done: \(String(describing: openArchivedParsed.done)), "
            + "archivedAt: \(String(describing: openArchivedParsed.archivedAt))"
    )

    // Restore: the symmetric mirror — append to tasks.md FIRST, strip the shard SECOND.
    let archiveLines = try vault.read(archiveURL).components(separatedBy: "\n")
    guard let (restoredBlockText, archiveRemaining) = TaskBlock.restoring(archiveLines, at: 0) else {
        print("Unexpected: the archived block didn't parse back — nothing restored.")
        return
    }

    let beforeRestore = try vault.read(tasksURL)
    let restoredTasks = beforeRestore.isEmpty ? restoredBlockText : beforeRestore + "\n" + restoredBlockText

    // STEP 3: tasks.md gets the restored, reopened block FIRST.
    try vault.writeAtomically(restoredTasks, to: tasksURL)
    print("\n--- STEP 3: restored block appended to tasks.md first ---")
    print(try vault.read(tasksURL))

    // STEP 4: the archive shard is only stripped once step 3 has actually landed.
    try vault.writeAtomically(archiveRemaining.joined(separator: "\n"), to: archiveURL)
    let afterRestoreShard = try vault.read(archiveURL)
    print("\n--- STEP 4: archive shard stripped of the restored block ---")
    print(afterRestoreShard.isEmpty ? "(empty — the shard held only that one block)" : afterRestoreShard)

    let restoredParsed = TaskBlock.parse(restoredBlockText, today: .today())!
    print("\n--- CHECK: the restored task is reopened, not just un-archived ---")
    print("isDone: \(restoredParsed.isDone), done: \(String(describing: restoredParsed.done)), archivedAt: \(String(describing: restoredParsed.archivedAt))")

    print("\nVault directory listing:")
    for name in try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() {
        print("  \(name)")
    }
    print("archive/ directory listing:")
    for name in try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("archive").path).sorted() {
        print("  \(name)")
    }
}

// The `--demo-archive <dir>` entry point, the archive's non-GUI proof path (mirrors
// `--demo-conflict-guard` above) — must run before AppKit is touched below.
if let flagIndex = CommandLine.arguments.firstIndex(of: "--demo-archive"),
   CommandLine.arguments.count > flagIndex + 1 {
    let demoDir = URL(fileURLWithPath: CommandLine.arguments[flagIndex + 1])
    do {
        try runArchiveDemo(in: demoDir)
        exit(0)
    } catch {
        FileHandle.standardError.write("Loaf: archive demo failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

/// The vault-root sidecar the morning routine writes when today needs a decision or a run
/// failed (ROADMAP.md → D2; DECISIONS.md 2026-08-23). A dotfile, so `VaultWatcher`'s `.md`
/// filter still catches changes to it while `Vault.notePaths()` skips it as a note.
let routineSignalFileName = ".routine-signal.md"

let routineDecisionTitle = "Loaf needs a decision"
/// Distinct from the decision title — a broken/failed run must read as louder, not as an
/// ordinary nudge (DESIGN.md → Trust: "Failure is loud").
let routineFailureTitle = "⚠️ Loaf run failed"

/// The notification body for a decision nudge: the one-line reason, plus each question as
/// its own bullet. The actual back-and-forth happens in a Claude Code chat, not the panel
/// (DESIGN.md → "The daily loop") — this is just the nudge to go there.
func routineDecisionBody(reason: String, questions: [String]) -> String {
    guard !questions.isEmpty else { return reason }
    return ([reason] + questions.map { "• \($0)" }).joined(separator: "\n")
}

/// The body of `--demo-signal`, factored out so it reads top-to-bottom as the demo script
/// it is. Reads `.routine-signal.md` from `vaultPath` (if present at all) through the real
/// `RoutineSignal.parse`/`SignalNudge.decide` logic from `LoafCore` and prints which
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
        FileHandle.standardError.write("Loaf: signal demo failed: \(error)\n".data(using: .utf8)!)
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

    /// Which HTML is currently loaded into the single `NoteWindow.webView` — the ordinary
    /// dashboard, or the minimal archive viewer swapped in over it (DECISIONS.md
    /// 2026-09-11 — no second `WKWebView`). Tracked so a repaint trigger (the watcher, the
    /// day-change/wake observers) refreshes whichever one is actually on screen instead of
    /// always snapping back to the dashboard.
    private enum PanelView { case dashboard, archive }
    private var currentView: PanelView = .dashboard
    /// Whether the window has had at least one full `load`. A same-view repaint patches the
    /// live document (`NoteWindow.refresh`), which needs a document to patch — so the very
    /// first paint must be a full load even though `currentView` already reads `.dashboard`.
    private var hasLoadedOnce = false

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
            NSLog("Loaf: couldn't bootstrap vault at \(vault.root.path): \(error)")
        }
        migrateFocusToken()

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
        menu.addItem(NSMenuItem(title: "View Archive", action: #selector(viewArchive), keyEquivalent: "a"))
        let themeItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        themeItem.submenu = buildThemeMenu()
        menu.addItem(themeItem)
        menu.addItem(NSMenuItem(title: "Open Vault in Finder", action: #selector(openVaultInFinder), keyEquivalent: "o"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Loaf", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        // Quit's target stays nil so terminate: routes down the responder chain to NSApp, which implements it.
        menu.items.forEach { item in
            item.target = (item.action == #selector(NSApplication.terminate(_:))) ? nil : self
        }
        return menu
    }

    /// The "Theme" submenu (DECISIONS.md 2026-09-11 — live theme switching, the picker
    /// half). Populated from `HTMLPage.availableThemeNames()` — every palette file under
    /// `Resources/themes/` — rather than a hardcoded list, so a new theme shows up here on
    /// its own. The checkmark tracks `config.theme`, which `buildMenu()`'s caller keeps
    /// current before rebuilding (see `selectTheme`).
    private func buildThemeMenu() -> NSMenu {
        let submenu = NSMenu()
        for name in HTMLPage.availableThemeNames() {
            let item = NSMenuItem(title: name.capitalized, action: #selector(selectTheme(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = name
            item.state = (name == config.theme) ? .on : .off
            submenu.addItem(item)
        }
        return submenu
    }

    /// Writes the picked theme to the config file, then repaints — `renderDashboard`/
    /// `renderArchiveView`'s own re-read (Part A) is what actually swaps the CSS live.
    /// Rebuilds the whole status-item menu afterward so the checkmark moves to the new
    /// selection.
    @objc private func selectTheme(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        do {
            try Config.setTheme(name)
        } catch {
            NSLog("Loaf: couldn't write theme \"\(name)\" to the config file: \(error)")
            return
        }
        config.theme = name
        statusItem?.menu = buildMenu()
        refreshCurrentView()
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

    @objc private func viewArchive() {
        renderArchiveView()
        guard let window else { return }
        if !window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Dashboard composition + rendering

    /// Reads exactly `brief.md`/`tasks.md`/`longterm.md` (`DashboardComposer`), buckets
    /// their tasks, and renders the four sections. No folder browser, no file picker.
    ///
    /// Buckets against `CalendarDate.effectiveToday()`, not `.today()` — the dashboard's
    /// "today" rolls over at 6am local, not midnight (DESIGN.md → "The daily loop").
    private func renderDashboard() {
        // A same-view repaint (a checkbox/focus/archive write-back, a watcher refresh, or a
        // live theme pick) patches the live document so the reader stays put with no flash;
        // only a switch INTO the dashboard from the archive view does a full load and starts
        // at the top. See NoteWindow.refresh vs .load.
        let sameView = currentView == .dashboard && hasLoadedOnce
        currentView = .dashboard
        // Live theme switching (DECISIONS.md 2026-09-11): the theme is no longer read
        // once at launch — every repaint re-reads it so a menu-bar pick (or a hand edit)
        // takes effect without a relaunch. The CSS itself already hot-reloads on repaint.
        config.theme = Config.load().theme
        let today = CalendarDate.effectiveToday()
        let dashboard = DashboardComposer.compose(vault: vault, today: today)
        let body = DashboardRenderer.renderBody(dashboard, today: today, soonWithinDays: config.soonWithinDays)
        if sameView {
            window?.refresh(body: body, css: HTMLPage.themeCSS(named: config.theme))
        } else {
            window?.load(html: HTMLPage.wrap(body: body, theme: config.theme), baseURL: vault.root)
        }
        hasLoadedOnce = true
    }

    /// The minimal archive viewer (DECISIONS.md 2026-09-11): swaps the same webView to a
    /// listing of the CURRENT month's archive shard, built by `ArchiveRenderer`. No second
    /// window/config — see `currentView`'s doc comment. Multi-month navigation is
    /// deferred; this only ever reads this month's shard.
    private func renderArchiveView() {
        let sameView = currentView == .archive && hasLoadedOnce
        currentView = .archive
        // See renderDashboard's matching re-read — live theme switching applies to
        // whichever view is actually being painted.
        config.theme = Config.load().theme
        let today = CalendarDate.effectiveToday()
        let archiveURL = Archive.archiveShardURL(for: Date(), vault: vault)
        let shardMarkdown = (try? vault.read(archiveURL)) ?? ""
        let shardRelativePath = "archive/\(archiveURL.lastPathComponent)"
        let body = ArchiveRenderer.renderBody(shardMarkdown, shardFile: shardRelativePath, today: today)
        if sameView {
            window?.refresh(body: body, css: HTMLPage.themeCSS(named: config.theme))
        } else {
            window?.load(html: HTMLPage.wrap(body: body, theme: config.theme), baseURL: vault.root)
        }
        hasLoadedOnce = true
    }

    /// Refreshes whichever view is actually on screen — used by repaint triggers that
    /// aren't themselves tied to a specific view (the watcher, wake/day-change).
    private func refreshCurrentView() {
        switch currentView {
        case .dashboard: renderDashboard()
        case .archive: renderArchiveView()
        }
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
        refreshCurrentView()
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

    /// One-time on-disk rename of the retired `★` placement glyph to the `today` token
    /// (DECISIONS.md 2026-09-11). Runs once at launch, BEFORE the watcher starts, so a
    /// migration write can't be mistaken for an external edit or race a pending toggle.
    /// Covers every shared file that could carry the token: `tasks.md` and `longterm.md`
    /// (a long-term goal can be pulled into Today too — ticket B7), and each existing
    /// `archive/*.md` shard (a focused task may have been archived). `TokenMigration`
    /// returns `nil` when a file has no `★`, so a clean vault is never rewritten and a
    /// second launch is a no-op — the parser accepts both spellings regardless, so nothing
    /// downstream depends on this having run.
    private func migrateFocusToken() {
        var targets = [vault.root.appendingPathComponent("tasks.md"),
                       vault.root.appendingPathComponent("longterm.md")]
        let archiveDir = vault.root.appendingPathComponent("archive", isDirectory: true)
        if let shards = try? FileManager.default.contentsOfDirectory(at: archiveDir, includingPropertiesForKeys: nil) {
            targets += shards.filter { $0.pathExtension == "md" }
        }

        for url in targets {
            guard let markdown = try? vault.read(url),
                  let migrated = TokenMigration.migrate(markdown) else { continue }
            do {
                try vault.writeAtomically(migrated, to: url)
            } catch {
                NSLog("Loaf: couldn't migrate the ★→today token in \(url.lastPathComponent): \(error) — the file is unchanged and still parses (both spellings are accepted)")
            }
        }
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

    private func startWatching() {
        let watcher = VaultWatcher(vault: vault) { [weak self] changedPaths in
            guard let self else { return }
            let changedNames = Set(changedPaths.map { $0.lastPathComponent })

            if changedNames.contains(routineSignalFileName) {
                DispatchQueue.main.async {
                    self.checkRoutineSignal()
                }
            }

            let dashboardFileChanged = changedNames.contains(where: { Self.dashboardFiles.contains($0) })
            // Only worth checking while the archive viewer is actually open — an external
            // edit to an old month's shard shouldn't yank the dashboard into view.
            let archiveShardChanged = self.currentView == .archive && changedPaths.contains(where: {
                $0.deletingLastPathComponent().lastPathComponent == "archive" && $0.pathExtension.lowercased() == "md"
            })
            guard dashboardFileChanged || archiveShardChanged else { return }
            DispatchQueue.main.async {
                self.refreshCurrentView()
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
                NSLog("Loaf: notification authorization request failed: \(error)")
            }
        }
    }

    /// Reads `.routine-signal.md` fresh from disk and posts the nudge it maps to (or
    /// nothing, on a clear day) — called once at launch and again whenever the watcher
    /// reports the signal file changed. All the actual decision logic
    /// (`RoutineSignal.parse` / `SignalNudge.decide`) lives in `LoafCore`, pure and
    /// unit-tested; this is just the AppKit-side wiring DESIGN.md's boundary keeps out of
    /// `LoafCore`.
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
                NSLog("Loaf: couldn't post notification \"\(title)\": \(error)")
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
