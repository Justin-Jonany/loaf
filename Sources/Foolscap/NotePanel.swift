import AppKit
import CoreGraphics
import WebKit

/// The note window: pinned to the macOS desktop layer, like a system desktop widget.
/// See DECISIONS.md (2026-08-16) for the rationale and the editing trade-off this
/// implies — desktop-level windows never receive keyboard focus, so in-widget text
/// editing does not work; editing is by editing the `.md` file directly (the user in
/// any editor, or an agent). `canBecomeKey`/`canBecomeMain` are false accordingly.
///
/// `level` sits one above `kCGDesktopWindowLevel` — above the wallpaper, behind every
/// ordinary app window and the Dock, and never over a fullscreen app. `.stationary`
/// keeps it out of the Spaces-switch animation (it doesn't travel to the active
/// Space — it's simply present on all of them), matching how desktop icons behave.
/// `.nonactivatingPanel` is kept on the styleMask so that, if a click ever *is*
/// delivered to it (see the checkbox-click investigation in ROADMAP.md), it doesn't
/// steal focus from whatever app you were in.
final class NotePanel: NSPanel {
    let webView: WKWebView

    init(contentRect: NSRect) {
        let configuration = WKWebViewConfiguration()
        // Only our own injected checkbox-toggle script runs (installTaskToggleHandler);
        // the renderer escapes any HTML/script found in the note itself, so this is safe.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        // WKWebView has no public API for this on macOS; `drawsBackground` is the
        // longstanding KVC-only way to make its default white page fill transparent so
        // frosted.css's `background: transparent` shows the NSVisualEffectView behind it.
        webView.setValue(false, forKey: "drawsBackground")

        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = false
        // One level above the desktop/wallpaper layer, below every ordinary window.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary]

        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false

        let effectView = NSVisualEffectView(frame: contentRect)
        effectView.blendingMode = .behindWindow
        effectView.material = .sidebar
        effectView.state = .active
        effectView.autoresizingMask = [.width, .height]

        // Borderless means there's no titlebar left to clear, so the web view is inset
        // by a small margin on every side instead of the old top-only strip: the bare
        // ring of NSVisualEffectView it exposes is what isMovableByWindowBackground grabs
        // to reposition the widget, and it frames the note like a desktop widget rather
        // than a window.
        webView.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 10),
            webView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 10),
            webView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -10),
            webView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -10),
        ])
        contentView = effectView

        setFrameAutosaveName("FoolscapPanel")
    }

    /// Loads rendered note HTML. `baseURL` should be the vault root so relative
    /// `attachments/…` image references in the markdown resolve.
    func load(html: String, baseURL: URL) {
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    /// Wires up checkbox write-back: registers `handler` under message name `toggleTask`
    /// and injects the script that listens for checkbox clicks and posts to it. Keeping
    /// the WKWebView plumbing here means the app target only ever sees `{line, checked}`.
    func installTaskToggleHandler(_ handler: WKScriptMessageHandler) {
        let controller = webView.configuration.userContentController
        controller.add(handler, name: "toggleTask")

        let source = """
        document.addEventListener('change', function (event) {
            var box = event.target;
            if (!(box instanceof HTMLInputElement) || box.type !== 'checkbox') { return; }
            var row = box.closest('.task');
            if (!row || !row.dataset.line) { return; }
            window.webkit.messageHandlers.toggleTask.postMessage({
                line: parseInt(row.dataset.line, 10),
                checked: box.checked
            });
        });
        """
        let script = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        controller.addUserScript(script)
    }

    // Desktop-level windows never take keyboard focus; there's no in-widget text
    // editing left for a key window to serve (see the type doc comment above).
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
