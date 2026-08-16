# Decisions

A running log of the decisions that shaped Foolscap — newest first. Each entry records what
was decided, why, and what it replaced, so a choice (and any later reversal) has a home that
ROADMAP (the plan) and CHANGELOG (shipped history) don't provide.

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
