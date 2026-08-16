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

Nothing is released yet. See [ROADMAP.md](ROADMAP.md) for what v0.1 requires.
