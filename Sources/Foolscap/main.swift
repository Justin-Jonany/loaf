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
              let line = (body["line"] as? NSNumber)?.intValue,
              let checked = (body["checked"] as? NSNumber)?.boolValue
        else { return }
        toggleTask(atLine: line, checked: checked)
    }

    /// Write-back for the metadata-below task format (stamping `✓done` on the metadata
    /// line, not the task line) is A4 (ROADMAP Wave 1) — split out on purpose because the
    /// write path is a distinct risk surface from parsing. Ticking a box in the dashboard
    /// is inert until A4 lands.
    private func toggleTask(atLine line: Int, checked: Bool) {}

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
