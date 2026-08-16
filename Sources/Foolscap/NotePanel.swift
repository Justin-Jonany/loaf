import AppKit
import WebKit

/// The note window: a normal-level, non-activating `NSPanel`.
///
/// `.nonactivatingPanel` is the whole reason this is a native app: clicking the note
/// does not deactivate whatever app you were in, so your cursor and menu bar stay put.
/// A panel does not accept key input by default, so `canBecomeKey` is overridden —
/// without it the text view silently refuses to take a keystroke. Despite the panel
/// styleMask, the window sits at ordinary (`.normal`) level and on one Space — it is
/// not an always-on-top float, and other windows can cover it.
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
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // Ordinary window behavior: lives on one Space, and other windows can cover it.
        // `.nonactivatingPanel` above and `hidesOnDeactivate = false` below are the only
        // pieces of "special panel" behavior kept from the original always-on-top design.
        isFloatingPanel = false
        level = .normal
        collectionBehavior = []

        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false

        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        let effectView = NSVisualEffectView(frame: contentRect)
        effectView.blendingMode = .behindWindow
        effectView.material = .sidebar
        effectView.state = .active
        effectView.autoresizingMask = [.width, .height]

        webView.frame = effectView.bounds
        webView.autoresizingMask = [.width, .height]
        effectView.addSubview(webView)
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

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
