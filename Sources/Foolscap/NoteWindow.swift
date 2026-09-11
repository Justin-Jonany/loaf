import AppKit
import WebKit

/// The note window: a plain, ordinary `NSWindow` — standard titlebar with all three
/// traffic lights, normal window level, becomes key/main like any document window.
/// No panel tricks: clicking it activates the app and brings it forward, same as any
/// other Mac app.
final class NoteWindow: NSWindow {
    let webView: WKWebView
    /// Stored so `applyReduceTransparency` can hide/show it later (ROADMAP X2 —
    /// Accessibility pass): the vibrant blur it provides is exactly what Reduce
    /// Transparency asks us to turn off.
    private let effectView: NSVisualEffectView

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

        let effectView = NSVisualEffectView(frame: contentRect)
        effectView.blendingMode = .behindWindow
        effectView.material = .sidebar
        effectView.state = .active
        effectView.autoresizingMask = [.width, .height]
        self.effectView = effectView

        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear

        webView.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: effectView.topAnchor),
            webView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
        ])
        contentView = effectView

        setFrameAutosaveName("FoolscapWindow")
    }

    /// Loads rendered note HTML. `baseURL` should be the vault root so relative
    /// `attachments/…` image references in the markdown resolve.
    func load(html: String, baseURL: URL) {
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    /// Wires up checkbox, focus-toggle, and archive/restore write-back: registers
    /// `handler` under message names `toggleTask`, `focusTask`, `archiveTask`,
    /// `restoreTask`, and `showDashboard`, and injects the script that listens for the
    /// corresponding DOM events and posts to them. Keeping the WKWebView plumbing here
    /// means the app target only ever sees plain `{file, line, ...}` messages — the
    /// dashboard (and the archive viewer, which swaps into the same webView) stitch
    /// several files, so each message carries its `data-file` (which note/shard)
    /// alongside `data-line` (where in it).
    func installTaskToggleHandler(_ handler: WKScriptMessageHandler) {
        let controller = webView.configuration.userContentController
        controller.add(handler, name: "toggleTask")
        controller.add(handler, name: "focusTask")
        controller.add(handler, name: "archiveTask")
        controller.add(handler, name: "restoreTask")
        controller.add(handler, name: "showDashboard")

        let source = """
        document.addEventListener('change', function (event) {
            var box = event.target;
            if (!(box instanceof HTMLInputElement) || box.type !== 'checkbox') { return; }
            var row = box.closest('.task');
            if (!row || !row.dataset.file || !row.dataset.line) { return; }
            window.webkit.messageHandlers.toggleTask.postMessage({
                file: row.dataset.file,
                line: parseInt(row.dataset.line, 10),
                checked: box.checked
            });
        });
        document.addEventListener('click', function (event) {
            var btn = event.target.closest && event.target.closest('.focus-toggle');
            if (!btn) { return; }
            var row = btn.closest('.task');
            if (!row || !row.dataset.file || !row.dataset.line) { return; }
            var nextFocus = btn.getAttribute('aria-pressed') !== 'true';
            window.webkit.messageHandlers.focusTask.postMessage({
                file: row.dataset.file,
                line: parseInt(row.dataset.line, 10),
                focus: nextFocus
            });
        });
        document.addEventListener('click', function (event) {
            var btn = event.target.closest && event.target.closest('.archive-button');
            if (!btn) { return; }
            var row = btn.closest('.task');
            if (!row || !row.dataset.file || !row.dataset.line) { return; }
            window.webkit.messageHandlers.archiveTask.postMessage({
                file: row.dataset.file,
                line: parseInt(row.dataset.line, 10)
            });
        });
        document.addEventListener('click', function (event) {
            var btn = event.target.closest && event.target.closest('.restore-button');
            if (!btn) { return; }
            var row = btn.closest('.task');
            if (!row || !row.dataset.file || !row.dataset.line) { return; }
            window.webkit.messageHandlers.restoreTask.postMessage({
                file: row.dataset.file,
                line: parseInt(row.dataset.line, 10)
            });
        });
        document.addEventListener('click', function (event) {
            var btn = event.target.closest && event.target.closest('.back-to-dashboard');
            if (!btn) { return; }
            window.webkit.messageHandlers.showDashboard.postMessage({});
        });
        """
        let script = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        controller.addUserScript(script)
    }

    /// Reduce Transparency (ROADMAP X2 — Accessibility pass, Hazards → Accessibility):
    /// forces the window to an opaque, non-vibrant appearance instead of the translucent
    /// frosted look. Hides `effectView` (turning off its blur/vibrancy outright) and makes
    /// the window itself opaque; `webView.drawsBackground` is switched back on so the page
    /// paints its own background rather than staying transparent over nothing, which is
    /// what lets `frosted.css`'s `prefers-reduced-transparency` fallback (`background:
    /// Canvas`) actually show. Called once at launch and again whenever `AppDelegate`
    /// observes `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` fire.
    func applyReduceTransparency(_ reduce: Bool) {
        effectView.isHidden = reduce
        isOpaque = reduce
        backgroundColor = reduce ? .windowBackgroundColor : .clear
        webView.setValue(reduce, forKey: "drawsBackground")
    }
}
