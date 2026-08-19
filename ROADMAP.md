# Roadmap

Nothing is released. The product is a **daily briefing panel** — the settled shape is in
[DESIGN.md](DESIGN.md); the visual language is in [design/mockup.html](design/mockup.html).
This is the work between here and something usable.

Ordering rule: **v0.1 is whatever makes Claude brief you every morning and you keep the panel
open for a week.** Everything that doesn't serve that is below the fold. See
[DECISIONS.md](DECISIONS.md) (2026-08-18) for why the "general markdown note widget" framing
this file used to carry was retargeted to the briefing product.

---

## v0.1 — A daily brief you keep open for a week

The bar: every morning Claude writes you a brief from your calendar, the panel shows it, you
tick things off, and when today needs a call Claude asks you.

### Already built (from the note-widget groundwork)
Reused as-is or nearly so — see [DECISIONS.md](DECISIONS.md):
- [x] Ordinary titled `NSWindow`: normal level, standard titlebar, key/main, Dock/Cmd+Tab
- [x] Frame persisted across restarts (`setFrameAutosaveName`)
- [x] Menu-bar `NSStatusItem` to show/hide, quit, open the vault in Finder
- [x] Load `*.md` from the vault; ignore dotfiles and `attachments/` (`Vault.notePaths`)
- [x] Create the vault + seed `CLAUDE.md` on first run (`Vault.bootstrapIfEmpty`)
- [x] `FSEvents` watcher with self-write suppression (`VaultWatcher` + self-write registry)
- [x] Atomic writes — temp file + `rename(2)` (`Vault.writeAtomically`)
- [x] Markdown → HTML in `WKWebView`; checkbox clicks write back to the line; ticking stamps
      the done marker

### Task model (the metadata-below format)
- [ ] Parse the new task shape: a checkbox line, an indented metadata line (`@due · source ·
      !priority · #type`), and optional indented note prose — replacing the old inline
      `due:`/`done:` key/value on the task line
- [ ] `@due` is **required**; parse `@today`/`@fri`/`@20aug`/ISO to date-only components
- [ ] Move the tick-a-box `✓done` stamp onto the metadata line (not the task line)
- [ ] `source` (`calendar`/`chat`/`manual`), `!priority`, `#type`, note — all parsed, most
      optional (see [DESIGN.md](DESIGN.md) → Tasks)

### The composed dashboard
- [ ] Compose the panel from three known files — `brief.md`, `tasks.md`, `longterm.md` — into
      one dashboard (this is stitching a fixed set, **not** a folder browser)
- [ ] **Today** and **This week** buckets computed by due date, each task in exactly one
      bucket (dedup: most-urgent wins)
- [ ] **Long-term** section from `longterm.md`; long-term items carry a far *target* `@due`
- [ ] Render tasks tidy — date chip, faint `#type`, priority dot, source icon — no raw
      `@`/`#` tokens visible
- [ ] Recompute buckets on wake and on day change; **rollover at 6am**, never on a timer

### The morning brief (a Claude routine — *not app code*)
- [ ] A scheduled **local** Claude Code run that reads Google Calendar + recent notes and
      writes `brief.md` (2–5 sentence recap) and proposes/updates tasks in `tasks.md`
- [ ] It asks the user (in a Claude Code chat) only when today needs a judgment call
- [ ] Writes a **change-log** of what it added/moved, with provenance for calendar tasks
- [ ] Stamps `brief.md` with build time; on failure, leaves a signal the app can surface

### Trust & reminders
- [ ] Panel shows the freshness stamp ("built 7:58am") from `brief.md`
- [ ] macOS notification when today needs a decision (app watches for the run's signal, or the
      run posts it) — silent on a clear day
- [ ] Loud failure path: stale/failed run nudges the user rather than looking current

### Config
- [ ] Read `~/.config/foolscap/config.toml`; every key optional
- [ ] `$FOOLSCAP_VAULT` overrides the vault path
- [ ] Ship `config.example.toml` fully commented (drop keys the briefing model doesn't use)

---

## v0.2 — Sharper

- [ ] Reminders at `@due` *times* (e.g. `@today T14:00` → notification at 2pm)
- [ ] `every:` recurrence — on completion, rewrite with the next `@due`
- [ ] Natural-language dates normalised on write (`@friday` → the ISO date)
- [ ] `card` and `console` themes (only `frosted` ships in v0.1)
- [ ] Auto-open Claude Code from the notification (v0.1 just notifies; you open it yourself)
- [ ] **Email as a source** — deferred from v0.1 for its noise/trust surface; needs a filter
      that keeps receipts and newsletters out of your tasks

---

## v0.3 — Rich content

- [ ] Mermaid fences rendered in the panel
- [ ] Images referenced from `attachments/` shown inline
- [ ] Syntax highlighting in fenced code blocks

---

## Hazards

Real engineering problems, cheaper to design for than to retrofit.

### FSEvents echo loop
Our own writes retrigger the watcher, which can clobber a concurrent change. Suppressed by
recording `(path, mtime, size)` for every write and ignoring matching events. Built
(`VaultWatcher`), still the load-bearing guard now that a scheduled run writes files under
the panel.

### Write conflicts on shared files
`tasks.md` and `longterm.md` are **shared** — you may edit one while the morning run rewrites
it. This is the common path, not an edge case. Last-write-wins silently destroys one side.
Minimum viable answer: if a file changed on disk since it was read and the app has an unsaved
change, keep the on-disk version, save the app's version to `<name>.conflict-<timestamp>.md`,
and tell the user. Per-section ownership (Brief = Claude, lists = shared) shapes the rule.

### Timezone and DST
Dates are date-only and timezone-naive. Never round-trip a `@due` through `Date` — it
reintroduces a timestamp and shifts the day across zones. Store/compare `DateComponents`.
`every:day` across a DST boundary is the test that catches a wrong implementation. The 6am
rollover must be computed in the local calendar, not off a UTC clock.

### Accessibility
- macOS **Reduce Transparency** must force `opacity = 1.0` and disable vibrancy
- **Increase Contrast** must strengthen the panel border
- Task rows in `WKWebView` need real checkbox semantics for VoiceOver, not styled `<div>`s
  (currently `<div class="task">` + a plain `<input type="checkbox">`; a proper ARIA pass is
  still owed)
- Respect `prefers-reduced-motion` in theme CSS

### Architecture fitness
`scripts/check-core-boundary.sh` fails CI if `Sources/FoolscapCore/` imports
AppKit/Cocoa/UIKit/SwiftUI/WebKit. Remaining gaps: a check that `FoolscapCore` has no
dependency on `Sources/Foolscap/` (true by convention only), and the VoiceOver gap above.

### Large vaults / staleness
Less pressing now — the panel composes only three files, so full re-parse per event is cheap.
If completed tasks accumulate in `tasks.md`, the morning run prunes those older than the
retrospective window (~7 days) so the file stays small.

### Distribution
Unsigned builds are Gatekeeper-blocked on first launch. Either document
`xattr -d com.apple.quarantine` in the README, or notarize with an Apple Developer account.
**Decide before the first release.**

### Sandboxing
Not sandboxed, so a vault anywhere on disk works, and a local Claude run can reach it. App
Store distribution would need security-scoped bookmarks — a structural change. Assume direct
distribution.

---

## Good first issues

- [ ] A new theme — one CSS file, no Swift
- [ ] README screenshots and a demo GIF
- [ ] Locale-aware date display (`19 Aug` vs `Aug 19`)
- [ ] `--vault` command-line flag
- [ ] Homebrew cask formula

---

## Out of scope for 1.0

Written down so it stays decided:

- **A folder / file browser.** The panel composes three known files; it is not a tree.
- **Claude / calendar / email inside the app.** The brains is an external run; the app has no
  API keys and makes no network calls.
- **A database.** The markdown files are the store; a rebuildable cache is the only escape
  hatch, and only if a huge vault ever demands it.
- **Email as a source (until v0.2+).** Calendar-only for now.
- **Time / effort estimates.** Dropped as noise.
- **Multi-device sync.** One device at a time.
- **Mobile / Windows / Linux.** macOS panel behaviour is the point.
- **A plugin system.** Themes are CSS; that is the extension surface.
- **Encryption.** Use FileVault.

---

## Open decisions

- [ ] **Name.** `foolscap` is a placeholder; it appears in `Info.plist`, `Package.swift`,
      `build.sh`, and the config path.
- [ ] **Gatekeeper** — document the workaround, or pay to notarize.
- [ ] **Where the run's "needs a decision" / failure signal lives** — a marker line in
      `brief.md`, or a small sidecar file the app watches.
