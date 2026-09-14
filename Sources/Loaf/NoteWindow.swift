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

        setFrameAutosaveName("LoafWindow")
    }

    /// Loads rendered note HTML with a full navigation. `baseURL` should be the vault root
    /// so relative `attachments/…` image references in the markdown resolve. Use this for
    /// the first paint and for a view SWITCH (dashboard↔archive), which should start at the
    /// top; a same-view repaint should go through `refresh` instead to hold scroll.
    func load(html: String, baseURL: URL) {
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    /// Repaints the SAME view in place, without a navigation: swaps the theme `<style>` and
    /// the body markup on the existing document and reapplies the scroll offset around the
    /// swap. A full `loadHTMLString` reload tears the document down and repaints from the
    /// top — a visible white flash plus a jump back to the first row on every checkbox
    /// toggle. Patching the live document avoids both: same document, so the delegated
    /// toggle/drag listeners (installed once on `document` by `installTaskToggleHandler`)
    /// stay live, relative image URLs still resolve against the original `baseURL`, and the
    /// reader stays put. Callers must have done an initial `load` first — there's no
    /// document to patch otherwise.
    func refresh(body: String, css: String) {
        let script = """
        (function () {
            var y = window.scrollY;
            var style = document.querySelector('style');
            if (style) { style.textContent = \(Self.jsStringLiteral(css)); }
            document.body.innerHTML = \(Self.jsStringLiteral(body));
            window.scrollTo(0, y);
        })();
        """
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    /// Encodes an arbitrary string as a JS string literal for embedding in an
    /// `evaluateJavaScript` source. A JSON string is a valid JS string literal, and this
    /// escapes the quotes, backslashes, and newlines that CSS/HTML are full of. (Serialized
    /// in a one-element array because `JSONSerialization` won't emit a bare top-level
    /// fragment; the brackets are then stripped.)
    private static func jsStringLiteral(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [s]),
              let json = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(json.dropFirst().dropLast())
    }

    /// Wires up checkbox, focus-toggle, reorder, and archive/restore write-back: registers
    /// `handler` under message names `toggleTask`, `focusTask`, `reorderTask`,
    /// `archiveTask`, `restoreTask`, and `showDashboard`, and injects the script that listens for the
    /// corresponding DOM events and posts to them. Keeping the WKWebView plumbing here
    /// means the app target only ever sees plain `{file, line, ...}` messages — the
    /// dashboard (and the archive viewer, which swaps into the same webView) stitch
    /// several files, so each message carries its `data-file` (which note/shard)
    /// alongside `data-line` (where in it).
    func installTaskToggleHandler(_ handler: WKScriptMessageHandler) {
        let controller = webView.configuration.userContentController
        controller.add(handler, name: "toggleTask")
        controller.add(handler, name: "focusTask")
        controller.add(handler, name: "reorderTask")
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

        // Drag-to-Today (DECISIONS.md 2026-09-11 — sticky drag placement replaces the ★
        // focus toggle). The small per-row handle (`.focus-toggle`, `draggable`) is the
        // drag SOURCE — scoped to the handle so a drag never swallows the checkbox/archive
        // clicks beside it. Dropping a row on a DIFFERENT section posts the SAME
        // `focusTask` write-back the click handler above does: `focus:true` onto Today,
        // `focus:false` onto any other section. `@due` is never touched. A drop that
        // wouldn't change the row's focus state is dropped as a no-op. A drop that stays
        // WITHIN Today instead reorders — see the `reorderTask` branch below (DECISIONS.md
        // 2026-09-14). Sections are matched by `data-section`, not their heading text.
        function dropSection(target) {
            return target && target.closest && target.closest('.dashboard section[data-section]');
        }
        document.addEventListener('dragstart', function (event) {
            var handle = event.target.closest && event.target.closest('.focus-toggle');
            if (!handle) { return; }
            var row = handle.closest('.task');
            if (!row || !row.dataset.file || !row.dataset.line) { return; }
            var srcSection = row.closest('section[data-section]');
            event.dataTransfer.effectAllowed = 'move';
            event.dataTransfer.setData('text/plain', JSON.stringify({
                file: row.dataset.file,
                line: parseInt(row.dataset.line, 10),
                focused: handle.getAttribute('aria-pressed') === 'true',
                fromSection: srcSection ? srcSection.dataset.section : null
            }));
        });
        document.addEventListener('dragover', function (event) {
            if (!dropSection(event.target)) { return; }
            event.preventDefault();               // required for the drop event to fire
            event.dataTransfer.dropEffect = 'move';
        });
        document.addEventListener('dragenter', function (event) {
            var section = dropSection(event.target);
            if (section) { section.classList.add('drop-target'); }
        });
        document.addEventListener('dragleave', function (event) {
            var section = dropSection(event.target);
            // dragleave fires crossing onto a child too; only clear when the pointer
            // actually left the section, not when it moved onto a descendant of it.
            if (section && !section.contains(event.relatedTarget)) {
                section.classList.remove('drop-target');
            }
        });
        document.addEventListener('drop', function (event) {
            var section = dropSection(event.target);
            if (!section) { return; }
            event.preventDefault();
            section.classList.remove('drop-target');
            var payload;
            try { payload = JSON.parse(event.dataTransfer.getData('text/plain')); } catch (e) { return; }
            if (!payload || !payload.file || !payload.line) { return; }
            // Reorder within Today (DECISIONS.md 2026-09-14): a task can be in Today
            // without the focus token (it's overdue/due-today on its own @due), so
            // `fromSection` — not `payload.focused` — is what identifies an intra-Today
            // drag. Cross-file interleaving isn't representable (Today lists tasks.md
            // before longterm.md), so a drop that would cross files is a no-op. This
            // branch always returns without posting focusTask, so reordering never
            // flips the today token.
            if (payload.fromSection === 'today' && section.dataset.section === 'today') {
                var targetRow = event.target.closest && event.target.closest('.task');
                if (targetRow && targetRow.dataset.file === payload.file && parseInt(targetRow.dataset.line, 10) !== payload.line) {
                    window.webkit.messageHandlers.reorderTask.postMessage({
                        file: payload.file,
                        line: payload.line,
                        beforeLine: parseInt(targetRow.dataset.line, 10)
                    });
                }
                return;
            }
            var wantFocus = section.dataset.section === 'today';
            if (wantFocus === payload.focused) { return; }   // already in the desired state
            window.webkit.messageHandlers.focusTask.postMessage({
                file: payload.file,
                line: payload.line,
                focus: wantFocus
            });
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
