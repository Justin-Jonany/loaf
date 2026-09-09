# Changelog

All notable changes to this project are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Repository scaffold, vault format specification, and theme system design.
- `FoolscapCore`: `CalendarDate` (timezone-naive), `Recurrence`, and `TaskLine`
  parsing for `due:`, `done:`, and `every:`, covered by 60 self-test checks.
- `NotePanel`: non-activating floating panel, plus a menu-bar item.
- `build.sh` assembles `dist/Foolscap.app` without Xcode.
- `Vault`: resolves the notes directory (`$FOOLSCAP_VAULT` → config → `~/Notes`), bootstraps
  it with the vault-side `CLAUDE.md` contract on first run, lists notes (ignoring dotfiles
  and `attachments/`), and writes atomically (temp file + `rename(2)`) with a self-write
  registry so the watcher can ignore its own echoes.
- `VaultWatcher`: `FSEvents`-based watcher that reports changed `.md` paths, filtered
  through the self-write registry.
- `MarkdownRenderer`: markdown → HTML via `swift-markdown` (new SPM dependency), with
  GFM task-list items special-cased into the `.task`/checkbox/`.due` markup `frosted.css`
  expects, driven by `TaskLine.urgency`.
- `Config`: hand-rolled reader for the documented subset of `~/.config/foolscap/config.toml`.
- The app now actually renders a note: on launch it loads config, bootstraps the vault,
  picks `todo.md` (or the first note alphabetically), renders it into the panel's `WKWebView`,
  and repaints on file changes via `VaultWatcher`. Added "Open Vault in Finder" to the menu.
- Self-test suite grown from 60 to 84 checks covering the above.
- `scripts/check-core-boundary.sh`: CI fitness function that fails the build if
  `Sources/FoolscapCore/` imports `AppKit`, `Cocoa`, `UIKit`, `SwiftUI`, or `WebKit`.
- Checkbox write-back: ticking a rendered checkbox re-reads the note from disk, toggles the
  matching `TaskLine` (stamping `done:<today>` on check, clearing it on uncheck), and writes
  it back atomically. `NotePanel` injects a `WKUserScript` that posts `{line, checked}` to a
  `toggleTask` message handler; `AppDelegate` re-renders once the write lands.
- Layout: the note body's top padding now clears the window's traffic-light buttons, and an
  all-task list renders flush (`ul.tasks`/`ol.tasks`) instead of with default bullet indent.
- `NotePanel` now sits at normal window level (`level = .normal`, empty `collectionBehavior`)
  instead of always-on-top/all-Spaces — it stays non-activating but can be covered by other
  windows, per updated ROADMAP guidance.
- Self-test suite grown from 84 to 89 checks (renderer `data-line`, non-disabled checkbox,
  and `tasks`-class list wrapping).
- `NotePanel`'s `WKWebView` is now inset 30px from the top of the window (Auto Layout,
  replacing the old frame/autoresizingMask setup) instead of filling it: the bare strip of
  `NSVisualEffectView` left above it is both the window's drag region and a mask so
  scrolled note content clips at the web view's top edge instead of sliding up under the
  traffic-light buttons. `frosted.css`'s `body` top padding is reverted to `13px` now that
  the native inset provides the buttons' clearance.
- `NotePanel` now sets `collectionBehavior = [.canJoinAllSpaces]` so the note is present on
  whatever Space/desktop you're on, instead of being pinned to the one it was created on.
  Window level (`.normal`) and non-activating behavior are unchanged — it's still not
  always-on-top and other windows can still cover it.

- `NotePanel` renamed to `NoteWindow` and rewritten as a plain `NSWindow`: standard titlebar
  with all three traffic lights, normal level, becomes key/main and activates the app like any
  ordinary document window. Drops the non-activating-panel trick, the `canJoinAllSpaces`
  cross-Space presence, and the top drag-strip inset (the web view now fills the content view
  edge-to-edge; dragging is via the real titlebar). The app's activation policy changed from
  `.accessory` to `.regular` (and `LSUIElement` removed from `Info.plist`) so it shows in the
  Dock and Cmd+Tab. See DECISIONS.md for why the desktop-widget model this replaces was tried
  and reverted without merging to `main`.
- `DashboardTaskRenderer` (`FoolscapCore`): tidies each dashboard task row into the plain
  sentence + a due-date chip + a faint `#type` tag + a priority dot + a source icon — no raw
  `@`/`#`/`!` tokens reach the DOM (DESIGN.md → Tasks: "Display ≠ storage"). `DashboardRenderer`
  now wraps this fragment instead of joining the raw metadata tokens into a `.meta` span.
  `frosted.css` gains `.type`/`.priority-dot`/`.source-icon` rules; the now-unused `.meta` rule
  is removed. Self-test suite grown to 187 checks.
- `CalendarDate.effectiveToday(in:now:rolloverHour:)`: the dashboard's "today" now rolls
  over at 6am local, not midnight, computed in the local calendar (never off a UTC clock).
  The app recomputes the dashboard on `NSWorkspace.didWakeNotification` and
  `NSCalendarDayChangedNotification` instead of `.today()` on every plain render — never a
  timer/poll. Self-test suite grown to 186 checks (rollover math, including the
  spring-forward and fall-back DST boundaries).
- `FoolscapCore`: `ConflictDecision`/`ConflictGuard`/`ConflictCopy` (X1 — shared-file
  write-conflict guard). If `tasks.md`/`longterm.md` changed on disk since the app read
  them (e.g. the morning run rewrote one) and the app has an unsaved change, the on-disk
  version is kept and the app's version is saved to `<name>.conflict-<timestamp>.md`
  instead of clobbering it; a disk change with no unsaved app change is a plain reload,
  no conflict file. Preserves `Vault`'s self-write suppression — a self-write is never
  mistaken for the concurrent external edit the guard exists to catch. Wired into the
  checkbox toggle write path in `Sources/Foolscap`, which now also shows a modal notice
  when a conflict is saved aside. `foolscap --demo-conflict-guard <dir>` is a non-GUI
  proof entry point (mirrors `--dump-dashboard`) that seeds a vault, simulates the race,
  and leaves the resulting BEFORE/AFTER files on disk.
- `FoolscapCore`: `RoutineSignal`/`SignalNudge` (D2 — decision notification + loud failure
  path). Parses the sidecar `.routine-signal.md` the morning run writes (DECISIONS.md
  2026-08-23) into a typed `status`/`at`/`reason`/`questions` value; an absent or blank
  file is `nil` (the clear-day state), and content that's present but doesn't parse into a
  recognized `status:` comes back tagged `.malformed` rather than being dropped.
  `SignalNudge.decide` maps that to the nudge the app should fire: nothing on a clear day,
  a normal "needs a decision" nudge for `needs-decision`, and a distinct, louder failure
  nudge for both `failed` and `.malformed` (DESIGN.md → Trust: "Failure is loud" — a broken
  signal must not read as silence). Wired into `Sources/Foolscap`: read at launch and
  whenever `VaultWatcher` reports `.routine-signal.md` changed, posted via
  `UNUserNotificationCenter` — the failure nudge uses a `.timeSensitive` interruption level
  and the critical sound to read as louder than the ordinary decision nudge.
  `foolscap --demo-signal <vault>` is a non-GUI proof entry point (mirrors
  `--demo-conflict-guard`) that reads a vault's `.routine-signal.md` and prints the
  title/body of the nudge it would fire.
- `DashboardComposer` (B6 — completed-today tasks linger until the 6am rollover): the
  bucket filter widens from "unchecked" to "unchecked or (`isDone` and `done == today`)",
  so ticking a box no longer drops the row instantly. A completed-today task keeps its
  `@due`-based section (Today/This week/Long-term, Long-term included) and sorts to the
  bottom, below the open items; an undated `[x]` (no `✓done` stamp) still never shows.
  `today` is the same rollover-aware value the caller already buckets against
  (`CalendarDate.effectiveToday`), so a completion drops on its own once "today" advances
  — no timer, no cleanup pass. `DashboardTaskRenderer` marks a done task's label with a
  `done` class (struck-through/dimmed); `DashboardRenderer` now also gives the row's `<li>`
  a `done` class and renders its checkbox `checked`, mirroring `MarkdownRenderer`'s
  existing convention for the single-note view. `frosted.css` gains a `.dashboard
  .task.done` rule dimming the chips alongside the struck-through sentence. Self-test
  suite grown to 228 checks.
- Accessibility pass (X2): `DashboardTaskRenderer.renderCheckbox` (`FoolscapCore`) gives
  each dashboard task row's `<input type="checkbox">` `role="checkbox"`, an `aria-checked`
  mirroring `isDone`, and an `aria-label` carrying the task sentence, so VoiceOver
  announces the row as a checkbox with its state and name instead of a bare, unlabelled
  checkbox — the native `checked` attribute and click-to-toggle path are unchanged.
  `frosted.css` gains `@media (prefers-contrast: more)` strengthening the panel border,
  section dividers, and each row's border (`prefers-reduced-motion` and the
  `prefers-reduced-transparency` CSS fallback already existed). `NoteWindow` gains
  `applyReduceTransparency`, wired to
  `NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency` and
  `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`: when Reduce
  Transparency is on, it hides the `NSVisualEffectView` (disabling vibrancy), makes the
  window opaque, and lets the `WKWebView` draw its own (now-opaque) CSS background.
  Self-test suite grown to 254 checks.

Nothing is released yet. See [ROADMAP.md](ROADMAP.md) for what v0.1 requires.
