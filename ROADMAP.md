# Roadmap

Nothing is released. The product is a **daily briefing panel** — the settled shape is in
[DESIGN.md](DESIGN.md); the visual language is in [design/mockup.html](design/mockup.html).
This is the work between here and something usable.

**The one bar:** every morning Claude writes you a brief from your calendar, the panel shows
it, you tick things off, and when today needs a call Claude asks you — and you keep the panel
open for a week without reaching for another app. The epics below are ordered toward that bar;
everything past Epic E is deliberately *after* it. See [DECISIONS.md](DECISIONS.md)
(2026-08-18) for why the "general markdown note widget" framing this file used to carry was
retargeted to the briefing product.

---

## How this roadmap works

This app is built with Claude, so the plan doubles as an execution spec.

- **Organised by epic, not version.** Each epic is a coherent slab of the product. Epics are
  ordered in **waves** (below): a wave lands before the next one starts; within a wave the
  tickets marked *parallel* can be separate PRs open at the same time.
- **A ticket = one PR.** Every ticket names its PR mapping and its `depends`/`blocks`. If a
  ticket ever needs two PRs it's split into two tickets first.
- **Every ticket states Problem / Solution / Tests / Verify.** The PR body uses the same four
  headings (see [.github/PULL_REQUEST_TEMPLATE.md](.github/PULL_REQUEST_TEMPLATE.md)).
- **Verify evidence matches the ticket type** — don't screenshot a parser:
  - *pure logic* (parser, bucketing, date math) → paste the green `swift test` run;
  - *rendering* (panel layout, chips, stamps) → a screenshot;
  - *behavioral / stateful* (tick-write, notifications, conflict handling) → a short
    screen-recording / GIF;
  - *the morning routine* (Epic C, not app code) → a run transcript + the vault `git diff`
    before/after.
- `[x]` shipped · `[ ]` open.

### Epic order at a glance

| Wave | Epics / tickets | Why here |
|---|---|---|
| **1** | **Epic A — Task parser** | The format contract everything else reads. Gates all of B and C. |
| **2** (parallel PRs) | **Epic B — Dashboard** ‖ **Epic C — Morning brief** ‖ **X1 — Conflict guard** | B and C both consume only A's *format*, not each other, so they run at once. X1 must land before C writes under the panel for real. |
| **3** | **Epic D — Trust & reminders** | Needs the dashboard (B) and the run's signals (C). Blocked on one open decision (signal location). |
| any time | **Epic E — Config** · **X2 — Accessibility pass** | Independent of the waves. |
| **after the bar** | **Epic F — Sharper** · **Epic G — Rich content** | Only once the daily brief has held for a week. |

---

## Done (from the note-widget groundwork)

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

---

## Wave 1

### Epic A — Task parser (the metadata-below format)

`FoolscapCore`, pure logic, no AppKit. The contract every downstream feature reads, so it
lands first.

- [ ] **A1 — Metadata-below parser** · 1 PR · depends: — · blocks: A4, all of B, C's format
  - **Problem:** The task format changed (DESIGN.md → Tasks): metadata moved off the task line
    onto an indented line beneath, so the task reads as prose. The old inline `due:`/`done:`
    parser can't read it, and buckets/rendering/the routine all depend on this format parsing
    right.
  - **Solution:** Parse the block — checkbox line, an indented metadata line
    (`@due · source · !priority · #type`), an optional further-indented note. Parse `@due`
    (required), `source` (`calendar`/`chat`/`manual`, `manual` implicit), `!priority`, `#type`,
    `every`, note. `@due` (`@today`/`@fri`/`@20aug`/ISO) → **date-only `DateComponents`**, never
    round-tripped through `Date` (DST hazard). Replaces inline `due:`/`done:`.
  - **Tests:** full block round-trips; `@due` required (missing → flagged); each `@due` form →
    correct components; absent optionals → defaults; date parse stable across a DST boundary.
  - **Verify:** *pure logic* — paste the green parser `swift test`.

- [ ] **A4 — Move the `✓done` stamp onto the metadata line** · 1 PR · depends: A1 · blocks: —
  - **Problem:** Ticking a box stamps the done marker on the *task* line (old format); it now
    belongs on the metadata line, and the write must not corrupt the block or trip the FSEvents
    echo loop.
  - **Solution:** Update the checkbox-write path to write `✓<date>` onto the metadata line only,
    keeping self-write suppression (`VaultWatcher`) and atomic write (`Vault.writeAtomically`).
    Split from A1 because the write path is a distinct risk surface.
  - **Tests:** tick adds `✓<date>` to the metadata line and nowhere else; un-tick removes it;
    a self-write doesn't retrigger a reload that clobbers a concurrent edit.
  - **Verify:** *behavioral* — GIF of ticking a box → the metadata line gaining `✓done` on disk.

---

## Wave 2 — parallel PRs

Epic B, Epic C, and ticket X1 can all have PRs open at once: B and C depend only on A's format.

### Epic B — The composed dashboard

Viewer UI. Depends on Epic A.

- [ ] **B1 — Assemble the dashboard from three known files** · 1 PR (B1+B2+B3) · depends: A1 ·
      blocks: B4, B5, D1
  - **Problem:** The panel must show a composed dashboard, not a folder listing — it stitches a
    fixed set of `brief.md`, `tasks.md`, `longterm.md` into four sections (DESIGN.md; no tree).
  - **Solution:** Read exactly those three files. **Today** = unchecked `@due` ≤ today;
    **This week** = unchecked due within the week not already in Today; each task renders in
    exactly one bucket, most-urgent wins (the dedup). **Long-term** from `longterm.md` (far
    *target* `@due`). Bucketing is pure logic, unit-testable.
  - **Tests:** due-today → Today not This-week (dedup); overdue → Today; due in 3 days → This
    week; a stray `notes.md` is ignored.
  - **Verify:** *rendering* — screenshot with all four sections populated · plus green bucketing
    tests.

- [x] **B4 — Tidy task rendering** · 1 PR · depends: B1 · blocks: X2
  - **Problem:** Raw `@`/`#`/`!` tokens must not show in the panel — display ≠ storage
    (DESIGN.md → Tasks).
  - **Solution:** Render each task as the sentence + a small date chip, a faint `#type` tag, a
    priority dot, and a source icon — no raw tokens. `frosted` theme only for v0.1.
  - **Tests:** rendered task DOM contains no literal `@`/`#`/`!`; a task with only `@due`
    renders cleanly.
  - **Verify:** *rendering* — before/after of one task, raw markdown vs. the chip/icon render.

- [x] **B5 — Recompute + 6am rollover** · 1 PR · depends: B1 · blocks: —
  - **Problem:** Buckets must recompute on day change, and "today" rolls over at **6am**, not
    midnight (DESIGN.md → daily loop). Off a UTC clock or a timer is the classic bug (Hazards →
    Timezone/DST).
  - **Solution:** Recompute on wake and on `NSCalendarDayChanged`, **never on a timer**; compute
    the 6am rollover in the **local calendar**.
  - **Tests:** 05:59 local → "today" is the previous day, 06:00 → it advances; rollover correct
    across a DST boundary; recompute fires on wake/day-change, not a poll.
  - **Verify:** *pure logic* — paste the green rollover + DST-boundary tests.

- [ ] **B6 — Completed-today tasks linger until the 6am rollover** · 1 PR · depends: B1, B4,
      B5 · blocks: —
  - **Problem:** Ticking a box stamps `✓done` (A4) and the row vanishes immediately, because
    every section shows only *unchecked* tasks (B1). You lose the "I did it" feedback and the
    panel keeps no trace of the day's progress until the next morning's brief.
  - **Solution:** Extend the bucket filter from "unchecked" to "unchecked **or** (`isDone` and
    `done == today`)". A completed-today task keeps its `@due`-based section, renders
    struck-through/dimmed, and sorts to the **bottom** of that section (open items first). "Today"
    is B5's 6am-rollover today, so at 6am yesterday's completions stop matching `done == today`
    and drop on their own — no timer, no cleanup pass. Applies to every section, **Long-term
    included**. An undated `[x]` (hand-edited, no `✓done`) does not show. The `✓done` line stays
    in `tasks.md` for the retrospective window; only the panel stops showing it. The morning
    brief remains where *past* days' completions are recapped.
  - **Tests:** completed-today shows in its bucket, struck-through, below open items;
    completed-yesterday does not show; undated `[x]` does not show; un-tick returns it to an open
    row; across the 6am boundary a task completed "today" drops once today advances; correct
    across a DST boundary.
  - **Verify:** *pure logic* — green bucketing + rollover selftest — **plus** *rendering* — a
    Playwright screenshot of the canonical fixture vault (decision-day) via `--dump-dashboard`
    showing struck-through done rows.

### Epic C — The morning brief routine — *not app code*

A scheduled **local** Claude Code run (prompt/skill + `CLAUDE.md` template + schedule config).
Depends only on A's *format*, so it runs parallel to Epic B.

- [ ] **C1 — The morning routine** · 1 PR · depends: A1's format · blocks: D1, D2 · parallel: B
  - **Problem:** The "brains" half is a scheduled local run, not Swift. Each morning it reads
    the calendar + recent notes and writes the vault so the viewer has something to show.
    Without it the dashboard is empty.
  - **Solution:** A scheduled run that reads Google Calendar + recent notes and writes `brief.md`
    (2–5 sentence recap) + proposes/updates `tasks.md` in the metadata-below format; asks the
    user (in a Claude Code chat) **only** when today needs a judgment call — silent on a clear
    day; writes a **change-log** of what it added/moved with **provenance** for calendar-derived
    tasks; stamps `brief.md` with build time; on failure leaves a signal the app can surface.
  - **Tests:** a dry-run against a fixture calendar + vault produces tasks A1 can parse; a clear
    day produces no interruption; a forced failure leaves the failure signal, not a stale brief.
  - **Verify:** *the routine* — run transcript + the `brief.md`/`tasks.md` `git diff`.

### Cross-cutting (Wave 2)

- [x] **X1 — Shared-file write-conflict guard** · 1 PR · depends: A4 · **must land before C runs
      live** (that's when a run starts writing under the panel)
  - **Problem:** `tasks.md`/`longterm.md` are **shared** — you may edit one while the run
    rewrites it (Hazards → Write conflicts). Last-write-wins silently destroys one side.
  - **Solution:** If a file changed on disk since it was read **and** the app has an unsaved
    change: keep the on-disk version, save the app's version to `<name>.conflict-<timestamp>.md`,
    tell the user. Per-section ownership (Brief = Claude-owned, lists = shared) shapes the rule.
  - **Tests:** disk-changed + dirty-buffer → on-disk kept, `.conflict-<ts>.md` written, user
    told; disk-changed + clean-buffer → plain reload, no conflict file.
  - **Verify:** *behavioral* — clip of a simulated concurrent write producing a `.conflict-`
    file + the notice.

---

## Wave 3

### Epic D — Trust & reminders

App-side. Needs the dashboard (B) and the run's signals (C).

- [ ] **D1 — Freshness stamp** · 1 PR · depends: B1, C1
  - **Problem:** Acting on a stale plan without knowing is the failure mode.
  - **Solution:** Parse the build-time stamp from `brief.md` and show it in Brief ("built
    7:58am").
  - **Tests:** stamp parsed from `brief.md`; missing/failed stamp → a clear "stale/unknown"
    state, not a fake time.
  - **Verify:** *rendering* — screenshot of Brief showing the stamp.

- [x] **D2 — Decision notification + loud failure path** · 1 PR (D2+D3) · depends: C1 +
      the signal-location decision (*settled 2026-09-09: sidecar `.routine-signal.md`* — see
      DECISIONS.md), so **no longer blocked**
  - **Problem:** The app must nudge (a) when today needs a decision and (b) when a run failed,
    while staying silent on a clear day. Both consume the same signal, so where it lives (marker
    line in `brief.md` vs. sidecar file) must be decided first.
  - **Solution:** macOS notification on the "needs a decision" signal — silent otherwise; a
    **loud failure path** so a stale/failed run nudges rather than looking current.
  - **Tests:** notification fires on a decision signal, nothing on a clear day; failure signal →
    a distinct failure nudge.
  - **Verify:** *behavioral* — clips of the decision notification and the failure nudge firing.

---

## Independent of the waves

### Epic E — Config

- [ ] **E1 — Config file + env override** · 1 PR · depends: —
  - **Problem:** The vault path and options need to be configurable, and the shipped example
    still lists keys the briefing model dropped (in-app editing).
  - **Solution:** Read `~/.config/foolscap/config.toml` (every key optional); `$FOOLSCAP_VAULT`
    overrides the vault path; ship `config.example.toml` fully commented with the dead
    in-app-editing keys removed.
  - **Tests:** absent config → defaults; partial config → only those keys override;
    `$FOOLSCAP_VAULT` wins over the config file path.
  - **Verify:** *pure logic* — paste the green config-precedence tests.

### Cross-cutting

- [ ] **X2 — Accessibility pass** · 1 PR · depends: B4 · label: accessibility
  - **Problem:** Task rows are styled `<div class="task">` + a plain `<input type="checkbox">`,
    so VoiceOver doesn't announce them as checkboxes (Hazards → Accessibility). Also owed:
    Reduce Transparency → opacity 1.0, Increase Contrast → stronger border,
    `prefers-reduced-motion`.
  - **Solution:** Give task rows real checkbox semantics (`role="checkbox"`/ARIA) and honor
    Reduce Transparency, Increase Contrast, and `prefers-reduced-motion` in theme CSS.
  - **Tests:** VoiceOver announces each row as a checkbox with its state; Reduce Transparency
    forces opacity 1.0 / disables vibrancy; Increase Contrast strengthens the border.
  - **Verify:** *behavioral* — screen-recording with VoiceOver audio + the Reduce-Transparency /
    Contrast states.

---

## After the bar

Only once the daily brief has held open for a week. Lighter detail — these get full
Problem/Solution/Tests/Verify tickets when pulled forward.

### Epic F — Sharper

- [ ] Reminders at `@due` *times* (`@today T14:00` → notification at 2pm)
- [ ] `every:` recurrence — on completion, rewrite with the next `@due`
- [ ] Natural-language dates normalised on write (`@friday` → the ISO date)
- [ ] `card` and `console` themes (only `frosted` ships before the bar)
- [ ] Auto-open Claude Code from the notification (before the bar it just notifies; you open it)
- [ ] **Email as a source** — deferred for its noise/trust surface; needs a filter that keeps
      receipts and newsletters out of your tasks

### Epic G — Rich content

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
Owned by ticket **X1**.

### Timezone and DST
Dates are date-only and timezone-naive. Never round-trip a `@due` through `Date` — it
reintroduces a timestamp and shifts the day across zones. Store/compare `DateComponents`.
`every:day` across a DST boundary is the test that catches a wrong implementation. The 6am
rollover must be computed in the local calendar, not off a UTC clock. Owned by tickets **A1**
and **B5**.

### Accessibility
- macOS **Reduce Transparency** must force `opacity = 1.0` and disable vibrancy
- **Increase Contrast** must strengthen the panel border
- Task rows in `WKWebView` need real checkbox semantics for VoiceOver, not styled `<div>`s
  (currently `<div class="task">` + a plain `<input type="checkbox">`; a proper ARIA pass is
  still owed)
- Respect `prefers-reduced-motion` in theme CSS

Owned by ticket **X2**.

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
- **Email as a source (until Epic F).** Calendar-only for now.
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
- [x] **Where the run's "needs a decision" / failure signal lives** — *settled 2026-09-09:*
      a sidecar dotfile `.routine-signal.md` at the vault root (the one C1 already ships), not a
      marker line in `brief.md`. See [DECISIONS.md](DECISIONS.md). **Unblocks ticket D2.**
