# Design

What Foolscap *is*, structurally — the app's shape and mental model. ROADMAP says what's
next and in what order; DECISIONS logs why things changed; this says what the thing is.

Settled 2026-08-18. Where a detail is a reasonable default rather than a hard commitment it's
marked _(default)_.

---

## What it is

**A daily briefing panel.** A small window that's always there and tells you what to do
today. You don't write in it much — Claude does. Each morning Claude reads your **calendar**
and your **recent notes** and writes you a plan: a short recap of where you're at, what's due,
what slipped from yesterday. Through the day you tick things off, and when today needs a
judgment call Claude can't make alone, it asks you.

It is **not** a note editor and **not** a file browser. There's no sidebar, no folder tree,
no "open any file." The panel shows a composed dashboard of the handful of things that matter
right now.

## The two halves

Foolscap is split in two, and the split is the whole architecture:

| | The **viewer** (this Swift app) | The **brains** (a scheduled Claude run) |
|---|---|---|
| What it is | A small macOS panel that composes a dashboard | A scheduled **local** Claude Code run — *not app code* |
| What it does | Displays the dashboard, lets you tick tasks, surfaces due dates, fires reminders | Reads calendar + recent notes, writes the brief and proposes tasks |
| What it knows about | The vault folder, and nothing else | Your calendar (via its own tools), and the vault |
| APIs / keys | **None.** No calendar, no email, no Claude embedded | Whatever the run needs lives in the run |

**The only thing connecting them is the vault folder.** The brains writes markdown files; the
viewer notices and repaints. This is the project's founding principle — *"there is no API;
notes are just files; an agent edits them; the widget watches"* — taken seriously: the app
never grows an integration, and the intelligence can be rerun or rewritten without touching
Swift.

## The panel — a composed dashboard

The viewer stitches a fixed set of files into one scrolling dashboard with four sections. It
is *not* a folder browser: it reads three known files, nothing else.

1. **Brief** — 2–5 sentences of prose Claude writes: what you got done yesterday and across
   the week, and what's slipping. This is the *only* place finished work shows up, since done
   tasks drop out of the lists below. Also carries the freshness stamp ("built 7:58am").
2. **Today** — every unchecked task with `@due` at or before today. That is spillover +
   due-tonight, computed automatically from due dates — nothing is stored as a literal "today
   list." Plus anything you or Claude explicitly add for today.
3. **This week** — unchecked tasks due within the week that aren't already shown in Today.
   (Each task renders in exactly one section — most-urgent bucket wins. That's the dedup.)
4. **Long-term** — target-dated goals. Shared: you and Claude both add and edit here.

Everything is **driven by due dates** — which is why every task has one. A task with no due
date couldn't be placed in any bucket.

## Tasks

A task is a GitHub-style checkbox. Its metadata lives on an **indented line beneath** it, not
strung along the task line — so the task reads as a plain sentence:

```markdown
- [ ] Prep the client deck
      @20aug · !high · #schoolwork · calendar
      Focus on the pricing slide — they pushed back last time.
- [ ] Email the landlord
      @today · manual
- [x] Read chapter 4
      @fri · #cs101 · ✓18aug
```

| Token | Required? | Meaning |
|---|---|---|
| `@due` | **required** | Due date (`@20aug`, `@today`, `@fri`, ISO). Buckets the task; drives colour/sort. |
| `source` | **required** | Where it came from: `calendar` · `chat` · `manual`. _(default)_ shown as a small muted panel icon; `manual` may be omitted as the implicit case. |
| `✓done` | auto | Stamped when you tick the box. |
| `!priority` | optional | `!high` / `!med` / `!low`. **On-command only** — Claude adds it when you ask, never automatically. Absent = normal. |
| `#type` | optional | A category tag: `#schoolwork`, `#cs101`, `#daily`, whatever you like. |
| note | optional | Free prose on a further indented line — context for the task. |
| `every` | optional | Recurrence (`every:week` …), from the existing model. |

**Display ≠ storage.** The block above is the *raw file*. The panel renders it tidy — the
sentence, a small date chip, a faint type tag, a priority dot, a source icon — with no raw
`@`/`#` tokens showing. It stays notes-style, not a Jira grid.

## Files in the vault

- `brief.md` — the prose summary, regenerated each run. **Claude-owned.**
- `tasks.md` — all dated tasks (Today + This-week buckets). Completed tasks stay here with
  `✓done` for ~7 days so the retrospective can read them, then Claude prunes. **Shared.**
- `longterm.md` — target-dated goals. **Shared** (mostly you, but Claude can discuss and edit).

Three tidy files. No `daily/YYYY-MM-DD.md` sprawl — the retrospective is prose, not an archive.

## The daily loop

```
  ~6am           a scheduled LOCAL Claude Code run fires
                 ├─ reads: Google Calendar + recent notes in the vault
                 ├─ writes: brief.md (recap) + proposes/updates tasks in tasks.md
                 └─ if today needs a judgment call → fires a macOS notification
                      │
                      ▼
  you            click the notification → a Claude Code chat asks its 2–3 questions
                 └─ you answer → it writes today's tasks → the panel repaints
                      │
                      ▼
  all day        the panel shows the dashboard; you tick boxes (writes ✓done back)
                 due times surface as reminders
```

- **Runs locally**, so it reads the vault directly and can post native notifications. It only
  runs when the Mac is awake; if it missed 6am it catches up on wake. _(default)_
- **Rollover is 6am**, not midnight — before 6am the panel still treats the previous day as
  "today."
- **It only interrupts you when today genuinely needs a decision** (spillover, something due
  tonight). A clear day is silent.
- The *conversation* happens in Claude Code (the terminal), because the app is a viewer and
  can't host a chat. The notification is the nudge to go there.

## Trust

Reading your data and inventing tasks is the scary part, so the brief shows its work:

- **Provenance.** Every task records its `source`; calendar-derived tasks (the ones you'd want
  to verify) carry a source marker, and the brief's **change-log** cites the specific origin —
  *"added 'prep deck' — from calendar event 'Client mtg 3pm'."*
- **Freshness.** The brief stamps when it was built, so you never act on a stale plan without
  knowing.
- **Failure is loud.** If a run fails (expired Google auth, API hiccup) it nudges you rather
  than leaving yesterday's brief sitting there looking current.

## Non-goals

Stated so they stay decided:

- **No folder / file browser in the app.** Considered and rejected. The panel composes three
  known files; it does not browse a tree.
- **No Claude, calendar, or email *inside* the app.** Those belong to the external run. The
  app has no API keys and makes no network calls of its own.
- **No database.** The markdown files *are* the store of record. A DB would duplicate state,
  fight the "notes are just files" philosophy, and buy nothing at personal scale. If speed
  ever bites on a huge vault, add a *rebuildable cache* — not a database.
- **No email (for now).** Sources are calendar + chat + manual. Email is a big, noisy trust
  surface; it's deferred, not designed-in.
- **No time/effort estimates.** Tried in planning, dropped as noise unless load-bearing.
- **No in-panel authoring workflow.** You *can* edit any file in any editor and the panel
  repaints, but Foolscap isn't where you sit and type. Claude fills it; you tick it; the
  long-term list you grow by talking to Claude or editing the file.
- **One device at a time.** Multi-Mac sync of the vault is out of scope.
