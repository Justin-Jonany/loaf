import AppKit
import WebKit
import LoafCore

runCommandLineToolIfRequested()

// Wires the vault + renderer into the window: load config, bootstrap the vault, compose
// the dashboard from the three known files, render it, and repaint whenever one of them
// changes on disk. The panel is a composed dashboard, not a folder browser (DESIGN.md →
// "The panel").

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler {
    var window: NoteWindow?
    private var statusItem: NSStatusItem?
    private var watcher: VaultWatcher?

    private var config = Config()
    var vault: Vault!

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
    static let dashboardFiles: Set<String> = ["brief.md", "tasks.md", "longterm.md"]

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
    func renderDashboard() {
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
    func renderArchiveView() {
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

}

let app = NSApplication.shared
// Ordinary app: shows in the Dock and Cmd+Tab, like any normal document window.
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
