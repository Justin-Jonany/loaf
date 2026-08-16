import AppKit
import FoolscapCore

// Scaffold only — see ROADMAP.md for what v0.1 still needs. This brings up the panel
// and the menu-bar item so the window behaviour can be verified in isolation before
// the vault and renderer are wired in.

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NotePanel?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = NotePanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 486))
        panel.contentView = NSVisualEffectView()
        panel.orderFrontRegardless()
        self.panel = panel

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "◳"
        item.menu = buildMenu()
        self.statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Notes", action: #selector(toggle), keyEquivalent: "n"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Foolscap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.items.forEach { $0.target = $0.action == #selector(toggle) ? self : nil }
        return menu
    }

    @objc private func toggle() {
        guard let panel else { return }
        panel.isVisible ? panel.orderOut(nil) : panel.orderFrontRegardless()
    }
}

let app = NSApplication.shared
// Agent app: menu bar only, never the Dock or the app switcher.
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
