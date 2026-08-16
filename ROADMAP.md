# Roadmap

Nothing is released. The design is settled ([design/mockup.html](design/mockup.html));
this is the work between here and something usable.

Ordering rule: **v0.1 is whatever makes it replace Stickies for one person.**
Everything that doesn't serve that is below the fold.

---

## v0.1 — Daily-drivable for one person

The bar: you keep it open for a week without reaching for another app, and Claude
can edit a note while you watch.

### Window — a desktop widget
The note pins to the macOS desktop layer (behind all app windows, present on every Space), like
a system desktop widget. See [DECISIONS.md](DECISIONS.md) (2026-08-16) for the rationale and the
editing trade-off.
- [x] Desktop-level window: sits behind app windows, never on top, never over fullscreen apps
      (`level = CGWindowLevelForKey(.desktopWindow) + 1`, verified against the real window
      server output — one above the wallpaper, below `kCGDesktopIconWindowLevel`, so it also
      sits behind Finder desktop icons)
- [x] Present on all Spaces (`canJoinAllSpaces`, `.stationary`)
- [x] Borderless; `isMovableByWindowBackground` to reposition when the desktop is visible
- [x] Frame persisted across restarts (`setFrameAutosaveName`)
- [x] Menu-bar `NSStatusItem` to show/hide, quit, and open the vault in Finder
- [ ] Investigate whether checkbox clicks register at desktop level; text editing is via the
      file. **Needs a human to verify** — this sandbox has neither Accessibility nor Screen
      Recording TCC permission, so a synthetic click can't be tested from here. To check:
      run `dist/Foolscap.app`, click a checkbox, and confirm the note's `.md` file picks up
      the `done:` stamp.

### Vault
- [ ] Load `*.md` from the configured directory; ignore dotfiles and `attachments/`
- [ ] Create the vault plus `CLAUDE.md` on first run if the directory is empty
- [ ] `FSEvents` watcher with **self-write suppression** (see Hazards — this one bites)
- [ ] Debounced write, ~600 ms after typing stops
- [ ] Flush on quit, on `NSWorkspace.willSleepNotification`, and on window close
- [ ] Atomic writes — temp file plus `rename(2)`, never truncate-in-place

### Rendering
- [ ] Markdown → HTML into a `WKWebView`
- [ ] Preview / Source toggle, remembered per session
- [ ] `frosted` theme complete; `card` and `console` can slip to v0.2
- [x] Checkbox clicks in preview write back to the underlying markdown line

### Dates
- [ ] Parse `due:` and `done:` from task lines
- [ ] Relative rendering — `today`, `2d over`, `19 Aug` — with the ISO date on hover
- [x] Ticking a box stamps `done:YYYY-MM-DD`
- [ ] Recompute relative dates on wake and on `NSCalendarDayChanged`, never on a timer

### Config
- [ ] Read `~/.config/foolscap/config.toml`; every key optional
- [ ] `$FOOLSCAP_VAULT` overrides the vault path
- [ ] Ship `config.example.toml` fully commented

---

## v0.2 — The reason to prefer it

- [ ] **Today view** — aggregate every unchecked `due:` at or before today across all
      notes. This is the feature that justifies dates existing; without it they're decoration.
- [ ] Daily notes: `daily/YYYY-MM-DD.md`, created on first write, from a template
- [ ] Note switcher (⌘K style) with fuzzy match
- [ ] Global hotkey for quick capture — append a line without opening the panel
- [ ] Full-text search across the vault
- [ ] `card` and `console` themes
- [ ] `every:` recurrence — on completion, rewrite the line with the next `due:`
- [ ] Natural-language dates in, ISO out (`due:friday` → `due:2026-08-14` on save)

---

## v0.3 — Rich content

- [ ] Mermaid fences rendered in preview
- [ ] Paste or drag an image → copied into `attachments/`, markdown reference inserted
- [ ] Syntax highlighting in fenced code blocks
- [ ] Wiki-links `[[note]]` between notes, with click-through

---

## Hazards

Real engineering problems, listed because each one is cheaper to design for than to
retrofit. None are optional.

### FSEvents echo loop
Our own writes retrigger the watcher, which reloads the buffer, which can clobber
what the user is typing. Suppress by recording `(path, mtime, size)` for every write
we make and ignoring events matching a recent entry. A bare debounce is not enough —
it turns into a race under fast typing.

### Write conflicts
A file can change on disk while the editor buffer is dirty — which is *exactly* the
Claude-edits-your-notes case, so it is the common path, not the edge case.
Last-write-wins silently destroys one side. Minimum viable answer: if the buffer is
dirty and the file changed, keep the on-disk version, write the buffer to
`note.conflict-<timestamp>.md`, and tell the user. Decide before v0.1 ships; the
storage layer's shape depends on it.

### Timezone and DST
Dates are date-only and timezone-naive. Never round-trip a due date through
`Date` — that reintroduces a timestamp and shifts the day across zones. Store and
compare `DateComponents` (year/month/day). `every:day` across a DST boundary is the
test case that catches a wrong implementation.

### Accessibility
- macOS **Reduce Transparency** must force `opacity = 1.0` and disable vibrancy
- **Increase Contrast** must strengthen the panel border
- A todo list rendered in `WKWebView` needs real checkbox semantics for VoiceOver,
  not styled `<div>`s (task rows are currently `<div class="task">` + a plain
  `<input type="checkbox">`; a proper `<li role="checkbox">`/ARIA pass is still owed)
- Respect `prefers-reduced-motion` in theme CSS

### Architecture fitness
`scripts/check-core-boundary.sh` now runs in CI and fails the build if
`Sources/FoolscapCore/` imports `AppKit`/`Cocoa`/`UIKit`/`SwiftUI`/`WebKit`, so the
hexagonal boundary is enforced, not just documented. Remaining fitness-function gaps:
a check that `FoolscapCore` has no dependency on `Sources/Foolscap/` (currently true by
convention only), and the VoiceOver semantics gap above.

### Large vaults
Re-parsing every file on every FSEvent is fine at 20 notes and unusable at 2,000.
Parse incrementally by path, and cache by mtime. Worth a benchmark before v0.2.

### Distribution
Unsigned builds are Gatekeeper-blocked on first launch. Either document
`xattr -d com.apple.quarantine` in the README, or pay for an Apple Developer
account and notarize. **Decide before the first release** — changing the answer
later means every early user hits the bad path.

### Sandboxing
Not sandboxed, so a vault anywhere on disk works. If this ever goes to the App
Store it needs security-scoped bookmarks for the vault directory — a structural
change, not a flag. Assume direct distribution unless that changes.

---

## Good first issues

Small, self-contained, no architectural context needed.

- [ ] A new theme — one CSS file, no Swift
- [ ] README screenshots and a demo GIF
- [ ] Locale-aware date display (`19 Aug` vs `Aug 19`)
- [ ] `--vault` and `--theme` command-line flags
- [ ] Homebrew cask formula
- [ ] Make `soon_within_days` actually respected by every theme's CSS

---

## Out of scope for 1.0

Written down so it stays decided:

- **Sync.** The vault is a folder; iCloud Drive and Dropbox already work. Not our problem.
- **Mobile / Windows / Linux.** macOS panel behaviour is the whole point.
- **A plugin system.** Themes are CSS; that is the extension surface.
- **WYSIWYG editing.** Source and preview, nothing between.
- **Encryption.** Use FileVault.

---

## Open decisions

- [ ] **Name.** `foolscap` is a placeholder; it appears in `Info.plist`,
      `Package.swift`, `build.sh`, and the config path.
- [ ] **Preview or source on open** — preview suits agent-authored content,
      source suits your own typing.
- [ ] **Gatekeeper** — document the workaround, or pay to notarize.
