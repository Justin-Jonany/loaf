import AppKit

/// The floating note window.
///
/// `.nonactivatingPanel` is the whole reason this is a native app: clicking the note
/// does not deactivate whatever app you were in, so your cursor and menu bar stay put.
/// A panel does not accept key input by default, so `canBecomeKey` is overridden —
/// without it the text view silently refuses to take a keystroke.
final class NotePanel: NSPanel {
    init(contentRect: NSRect) {
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

        setFrameAutosaveName("FoolscapPanel")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
