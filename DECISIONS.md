# Decisions

A running log of the decisions that shaped Foolscap — newest first. Each entry records what
was decided, why, and what it replaced, so a choice (and any later reversal) has a home that
ROADMAP (the plan) and CHANGELOG (shipped history) don't provide.

## 2026-09-09 — Write-conflict guard: modal notice, wired at the checkbox-toggle write path (ticket X1)

**Decided:** the X1 guard's "unsaved app change" is the in-flight write a checkbox toggle
produces (read tasks.md/longterm.md → apply the toggle in memory → write it back), not a
general editing buffer — DESIGN.md's non-goals rule out an in-panel authoring workflow, so
there's no other place in the app where an "unsaved change" currently exists. The user notice
for a caught conflict is a blocking `NSAlert`, not a background notification.

**Why:** the toggle path is the only real read-then-write race the app has today, and it's
exactly the shape ROADMAP's hazard describes (the morning run rewrites a shared file while the
app has a pending write based on a now-stale read) — no synthetic "dirty" state was needed to
exercise the rule for real. A modal alert was chosen over a notification because ticket D2
("Decision notification + loud failure path") owns the app's real notification/signal surface
and is still blocked on an open decision (where the signal lives); a write conflict is rare
enough that a synchronous dialog at the moment it happens is preferable to inventing a second,
throwaway notification path ahead of D2. If D2 lands a general notification mechanism first,
X1's alert can be swapped for it without changing the guard logic itself — `ConflictDecision`
and `ConflictGuard` (`FoolscapCore`) know nothing about how the caller informs the user.

**Status:** shipped. Not a reversal of anything; extends the hazard already logged in
ROADMAP.md → Hazards → "Write conflicts on shared files."

## 2026-08-23 — Morning routine signal: provisional sidecar file (ticket C1)

**Decided (provisionally):** the routine's "needs a decision" / "failed" signal is a small
dotfile, `.routine-signal.md`, at the vault root — `status: needs-decision|failed`, `at:`
(ISO 8601, same shape as the `brief.md` build stamp), `reason:`, and (for a decision)
`questions:`. Absence of the file is the "clear day, nothing to see" state.

**Why this shape:** it fires `VaultWatcher`'s existing `.md`-extension filter with no watcher
code changes (a dotfile is still `*.md`), while `Vault.notePaths()` already skips dotfiles, so
it never shows up as a note in the panel. It also keeps `brief.md` pure human-readable prose
rather than mixing in a machine-parsed control line.

**This is NOT the final call.** ROADMAP.md's "Open decisions" explicitly leaves *where this
signal lives* — this sidecar file vs. a marker line in `brief.md` — to ticket **D2**, which
owns the app-side consumer. C1 needed something concrete and testable to ship against; the
exact shape is deliberately isolated to one write path in `routines/morning-brief/` (see
`SKILL.md` -> "The decision / failure signal") so D2 can change it without touching the
routine's actual judgment logic.

**Status:** shipped as C1's provisional default; final shape owned by D2.

## 2026-08-18 — Product direction: Foolscap is a daily-briefing panel

**Decided:** Foolscap is a **daily briefing panel**, not a generic markdown note widget. Each
morning Claude reads the user's calendar and recent notes and writes them a plan; the panel
displays it and the user ticks it off. The full shape lives in [DESIGN.md](DESIGN.md); the
load-bearing choices:

- **Dumb viewer + external brains.** The Swift app stays a viewer with no API keys and no
  network calls. A scheduled **local** Claude Code run is the "brains" — it reads calendar +
  notes and writes markdown into the vault; the app watches and repaints. The vault folder is
  the *only* interface between them. This is the existing "there is no API; notes are files;
  an agent edits them; the widget watches" principle, taken literally.
- **Composed dashboard, four sections:** a prose **Brief** (2–5 sentence recap — the only
  place finished work shows), **Today** and **This week** (both *computed by due date*, not
  stored lists; each task renders in one bucket — that's the dedup), and **Long-term**
  (target-dated goals, shared). The app stitches three known files; it does **not** browse a
  folder tree.
- **Every task has a due date and a source.** Rendering is entirely due-date-driven, so a due
  date is mandatory (long-term items get a far *target* date). Source (`calendar`/`chat`/
  `manual`) is recorded for provenance. Optional: `!priority` (on-command only), `#type` tag,
  a free-text note. Metadata sits on an **indented line below** the task so the task reads as
  plain prose; the panel renders it as chips/icons, not raw tokens. No effort/time estimates.
- **Interaction is a notification → Claude Code chat.** The run notifies only when today needs
  a judgment call; the conversation happens in the terminal (the viewer can't host a chat).
  Rollover at 6am.
- **Trust surfaces:** provenance citations + a change-log of what Claude added/moved, a "built
  HH:MM" freshness stamp, and a loud failure nudge.

**Why:** The user's actual goal is "a panel that tells me what to do today," assembled from
calendar/notes by Claude — not a place to hand-write notes. Naming that explicitly collapses a
lot of prior ambiguity (folder-browser vs. widget, embedded vs. external agent) and lets most
of the existing v0.1 primitives be pointed at a purpose instead of reinvented.

**Rejected along the way:** a folder/file-browser view; an agent embedded inside the app; a
local database (the markdown files are the store; add a rebuildable cache only if a huge vault
demands it); reading **email** (deferred — calendar-only for now); time/effort estimates.

**Supersedes:** the ROADMAP framing that treated Foolscap as a general markdown note widget
whose reason-to-exist was a v0.2 "Today view." The Today view is now core. In-panel text
editing — floated as a possibility in the 2026-08-16 revert entry below — is explicitly *not*
the direction: editing goes through Claude or an external editor, so the debounced-write /
flush-on-quit items in ROADMAP's old Vault section fall away.

**Status:** designed, not yet built.

## 2026-08-16 — Window model: revert to an ordinary window

**Decided:** Drop the desktop-widget model below. `NoteWindow` is now a plain `NSWindow`:
standard titlebar with all three traffic lights, normal window level, becomes key/main and
activates the app like any other document window — no panel tricks, no pinned level, no
cross-Space presence.

**Why:** Built and ran the desktop-widget model; it felt wrong in practice — no keyboard
focus, sitting behind Finder's desktop icons, no window chrome to grab or resize by. The
"glanceable widget" framing didn't outweigh how unfamiliar it felt to actually use.

**Consequence:** In-widget text editing is back on the table as a future possibility, since
the window can hold keyboard focus again — not built in this change, but no longer blocked by
the window model the way it was under the desktop-widget trade-off below.

**Supersedes:** the desktop-widget entry immediately below, which was implemented and then
reverted without ever merging to `main`.

**Status:** implemented.

## 2026-08-16 — Window model: desktop widget (reverted — see the entry above)

**Decided:** Pin the note to the macOS desktop/wallpaper layer — behind all app windows,
present on all Spaces — like a system desktop widget.

**Why:** The user wants a glanceable widget that never floats on top and never intrudes on
fullscreen apps; at desktop level there is nothing to minimize and nothing to fight for front.

**Trade-off:** Windows at desktop level do not receive keyboard focus, so **in-widget text
editing will not work** — editing is by editing the `.md` file (the user in any editor, or an
agent). Whether a checkbox can be *clicked* to tick at desktop level is unverified (TBD on
implementation).

**Supersedes:** the original always-on-top floating `.floating` `NSPanel`, and a
briefly-considered "convert to a normal app window" direction. The window changes already on
the open slice-2 PR (`level = .normal`, `collectionBehavior = [.canJoinAllSpaces]`, the top
drag-strip inset) are **interim** and will be reworked when this model is built.

**Status:** implemented, then reverted — see the entry above.

## 2026-08-16 — Menu-bar Quit routed to NSApp

**Decided:** The Quit menu item's target is left `nil` so `terminate:` routes down the
responder chain to `NSApp`.

**Why:** Pointing every menu item at the app delegate disabled Quit (the delegate does not
implement `terminate:`), greying it out.

## 2026-08-15 — Repo & workflow: private GitHub, PR-per-slice

**Decided:** The repo is private; `main` takes no direct commits; each slice of work goes on a
feature branch and opens a draft PR the user reviews and merges.

**Why:** The user drives review/merge and wants `main` kept clean.

## 2026-08-15 — Markdown rendering: depend on swift-markdown

**Decided:** Use `swift-markdown` (pinned 0.8.0) to parse CommonMark+GFM to an AST, rendered to
HTML in `FoolscapCore`; task-list items are re-parsed through `TaskLine` so `due:`/`done:`/
`every:` semantics survive.

**Why:** Correct markdown without hand-rolling a parser; it still builds with plain
`swift build` (no Xcode), consistent with the project's "no Xcode required" stance.

## 2026-08-15 — Config: hand-rolled reader, no TOML dependency

**Decided:** Read the documented subset of `config.toml` with a small key/value reader; add no
TOML library.

**Why:** Keep the dependency surface minimal; full TOML fidelity is not needed.

## 2026-08-15 — Architecture: hexagonal core boundary, enforced

**Decided:** `FoolscapCore` imports no UI frameworks (AppKit/Cocoa/UIKit/SwiftUI/WebKit);
`scripts/check-core-boundary.sh` fails CI if it does.

**Why:** Keep the domain logic GUI-free and self-testable, and stop the boundary from rotting
silently.

---

**Still open** (tracked in [ROADMAP.md](ROADMAP.md) → Open decisions): the app name (`foolscap`
is a placeholder), Gatekeeper/notarization vs. documenting the workaround, and preview-vs-source
on open.
