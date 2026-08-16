import AppKit
import WebKit

/// The floating note window.
///
/// `.nonactivatingPanel` is the whole reason this is a native app: clicking the note
/// does not deactivate whatever app you were in, so your cursor and menu bar stay put.
/// A panel does not accept key input by default, so `canBecomeKey` is overridden —
/// without it the text view silently refuses to take a keystroke.
final class NotePanel: NSPanel {
    let webView: WKWebView

    init(contentRect: NSRect) {
        let configuration = WKWebViewConfiguration()
        // Stays off this slice: the rendered note is read-only, and there's no script to run.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
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

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

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

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
