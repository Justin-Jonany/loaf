import AppKit
import FoolscapCore

// Wires the vault + renderer into the panel: load config, bootstrap the vault, pick a
// note, render it, and repaint whenever the file changes on disk. This is the
// Claude-edits-your-note-and-the-widget-repaints demo — see ROADMAP for what's next.

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NotePanel?
    private var statusItem: NSStatusItem?
    private var watcher: VaultWatcher?

    private var config = Config()
    private var vault: Vault!
    private var currentNotePath: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        config = Config.load()
        vault = Vault(root: Vault.resolveRoot(config: config))
        do {
            try vault.bootstrapIfEmpty()
        } catch {
            NSLog("Foolscap: couldn't bootstrap vault at \(vault.root.path): \(error)")
        }

        let panel = NotePanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 486))
        panel.orderFrontRegardless()
        self.panel = panel

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "◳"
        item.menu = buildMenu()
        self.statusItem = item

        showInitialNote()
        startWatching()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Notes", action: #selector(toggle), keyEquivalent: "n"))
        menu.addItem(NSMenuItem(title: "Open Vault in Finder", action: #selector(openVaultInFinder), keyEquivalent: "o"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Foolscap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        return menu
    }

    @objc private func toggle() {
        guard let panel else { return }
        panel.isVisible ? panel.orderOut(nil) : panel.orderFrontRegardless()
    }

    @objc private func openVaultInFinder() {
        NSWorkspace.shared.open(vault.root)
    }

    // MARK: - Note selection + rendering

    /// `todo.md` if present, else the first `*.md` alphabetically. A real switcher is v0.2.
    private func pickInitialNote() -> URL? {
        let notes = vault.notePaths()
        return notes.first { $0.lastPathComponent == "todo.md" } ?? notes.first
    }

    private func showInitialNote() {
        guard let noteURL = pickInitialNote() else { return }
        currentNotePath = noteURL
        renderAndShow(noteURL)
    }

    private func renderAndShow(_ noteURL: URL) {
        guard let markdown = try? vault.read(noteURL) else { return }
        let body = MarkdownRenderer.renderHTML(
            from: markdown,
            today: .today(),
            soonWithinDays: config.soonWithinDays
        )
        panel?.load(html: Self.wrapHTML(body: body, theme: config.theme), baseURL: vault.root)
    }

    private func startWatching() {
        let watcher = VaultWatcher(vault: vault) { [weak self] changedPaths in
            guard let self, let current = self.currentNotePath else { return }
            let currentResolved = current.resolvingSymlinksInPath()
            guard changedPaths.contains(where: { $0.resolvingSymlinksInPath() == currentResolved }) else { return }
            DispatchQueue.main.async {
                self.renderAndShow(current)
            }
        }
        watcher.start()
        self.watcher = watcher
    }

    // MARK: - Theming

    private static func wrapHTML(body: String, theme: String) -> String {
        let css = loadThemeCSS(named: theme) ?? loadThemeCSS(named: "frosted") ?? ""
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>\(css)</style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    /// Only `frosted` ships fully styled this slice — `card`/`console` are a later slice
    /// (see ROADMAP) — so any other name falls back to it. CSS is inlined rather than
    /// linked: the theme lives next to the app bundle, not in the vault, so a `<link
    /// href>` relative to the `loadHTMLString` baseURL (the vault root) wouldn't resolve.
    private static func loadThemeCSS(named name: String) -> String? {
        var candidates: [URL] = []
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("themes/\(name).css"))
        }
        let sourceDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        candidates.append(sourceDir.appendingPathComponent("../../Resources/themes/\(name).css").standardized)

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            return try? String(contentsOf: candidate, encoding: .utf8)
        }
        return nil
    }
}

let app = NSApplication.shared
// Agent app: menu bar only, never the Dock or the app switcher.
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
