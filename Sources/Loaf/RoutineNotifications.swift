import Foundation
import UserNotifications
import LoafCore

/// The vault-root sidecar the morning routine writes when today needs a decision or a run
/// failed (DECISIONS.md 2026-08-23). A dotfile, so `VaultWatcher`'s `.md`
/// filter still catches changes to it while `Vault.notePaths()` skips it as a note.
let routineSignalFileName = ".routine-signal.md"

let routineDecisionTitle = "Loaf needs a decision"
/// Distinct from the decision title — a broken/failed run must read as louder, not as an
/// ordinary nudge (DESIGN.md → Trust: "Failure is loud").
let routineFailureTitle = "⚠️ Loaf run failed"

/// The notification body for a decision nudge: the one-line reason, plus each question as
/// its own bullet. The actual back-and-forth happens in a Claude Code chat, not the panel
/// (DESIGN.md → "The daily loop") — this is just the nudge to go there.
func routineDecisionBody(reason: String, questions: [String]) -> String {
    guard !questions.isEmpty else { return reason }
    return ([reason] + questions.map { "• \($0)" }).joined(separator: "\n")
}

extension AppDelegate {
    // MARK: - Decision / failure notification

    /// Asks macOS for permission to post user notifications. Fired once at launch; if the
    /// user has already answered (or denied) this is a no-op beyond the one system call.
    /// Silent about the outcome beyond logging — nothing downstream needs to branch on it:
    /// a denied request just means `add(_:)` below quietly does nothing, same as any other
    /// notification-disabled app.
    func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                NSLog("Loaf: notification authorization request failed: \(error)")
            }
        }
    }

    /// Reads `.routine-signal.md` fresh from disk and posts the nudge it maps to (or
    /// nothing, on a clear day) — called once at launch and again whenever the watcher
    /// reports the signal file changed. All the actual decision logic
    /// (`RoutineSignal.parse` / `SignalNudge.decide`) lives in `LoafCore`, pure and
    /// unit-tested; this is just the AppKit-side wiring DESIGN.md's boundary keeps out of
    /// `LoafCore`.
    func checkRoutineSignal() {
        let signalURL = vault.root.appendingPathComponent(routineSignalFileName)
        // An unreadable-but-present file (permissions, non-UTF8 content, ...) collapses to
        // the same "" as a genuinely absent one; `RoutineSignal.parse("")` is `nil` either
        // way, so both read as the clear-day state rather than a spurious failure nudge.
        let text = (try? vault.read(signalURL)) ?? ""
        postNudge(SignalNudge.decide(for: RoutineSignal.parse(text)))
    }

    private func postNudge(_ nudge: SignalNudge) {
        switch nudge {
        case .none:
            break // Silent on a clear day (DESIGN.md → Trust) — no notification at all.
        case .decision(let reason, let questions):
            postNotification(
                title: routineDecisionTitle,
                body: routineDecisionBody(reason: reason, questions: questions),
                interruptionLevel: .active,
                sound: .default
            )
        case .failure(let reason):
            // Distinct from the decision nudge, not just a different string: a
            // time-sensitive interruption level (can pierce Focus filtering that would
            // hold back an ordinary notification) plus the critical sound — DESIGN.md →
            // Trust: "Failure is loud," so a failed/broken run must not read as an
            // ordinary nudge, let alone stay silent like a clear day.
            postNotification(
                title: routineFailureTitle,
                body: reason,
                interruptionLevel: .timeSensitive,
                sound: .defaultCritical
            )
        }
    }

    private func postNotification(
        title: String, body: String, interruptionLevel: UNNotificationInterruptionLevel, sound: UNNotificationSound
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound
        content.interruptionLevel = interruptionLevel

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("Loaf: couldn't post notification \"\(title)\": \(error)")
            }
        }
    }
}
