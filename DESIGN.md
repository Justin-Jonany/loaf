# Design

What Loaf *is*, structurally — the app's shape and mental model. ROADMAP says what's
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

Loaf is split in two, and the split is the whole architecture:

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

## Single source: the task format lives in one file

The task format — the metadata-below shape, its tokens, its rules — is authored **once**,
in the repo's [`TASK-FORMAT.md`](TASK-FORMAT.md). Nothing else restates it:

- The morning-brief routine injects it into its prompt (`routines/morning-brief/run.sh`
  reads the file and hands it to the run).
- The `loaf-notes` and `loaf-brief` skills read it directly, via the `contract` pointer
  in `~/.config/loaf/config.toml` (written by `scripts/install.sh`, pointing at the copy
  it keeps in `~/Library/Application Support/Loaf/`).

Skills and the routine *reference* `TASK-FORMAT.md`; they never restate it. This used to be
duplicated across the vault's `CLAUDE.md` template, the morning-brief SKILL, and the
loaf-notes SKILL — three copies that drifted apart over time. A vault's own `CLAUDE.md` is
now the user's personal context only (tone, priorities, the people in their life) — never
the format — so it never needs editing when the format changes.

The brief itself is an **insight layer**, not a restatement of the task list: it surfaces
only what the list can't show on its own — spillover, an unusually heavy or light day, a
scheduling collision, a resolved ambiguity. One phrase is a valid brief; four sentences is
a hard cap; it never pads to fill space when there's nothing worth noting.

## The panel — a composed dashboard

The viewer stitches a fixed set of files into one scrolling dashboard with four sections. It
is *not* a folder browser: it reads three known files, nothing else.

1. **Brief** — 2–5 sentences of prose Claude writes: what you got done yesterday and across
   the week, and what's slipping. It's where *past* days' finished work is recapped, but a
   completed task isn't only there — it stays visible struck-through in its own section
   (below) until you archive it. Also carries the freshness stamp ("built Sep 23, 7:58am").
2. **Today** — every task with `@due` at or before today (spillover + due-tonight, computed
   automatically from due dates), **plus any task you've _starred_ (`★`) for today**, whatever
   its deadline. Nothing is stored as a literal "today list": the due-date part is derived, and
   the starred part is a per-task flag you set from the panel (see Focus, below) — a starred
   task keeps its real `@due` and simply surfaces here instead of its due-date bucket. A task
   you complete stays here struck-through, in place, until you archive it.
3. **This week** — tasks due within the week that aren't already shown in Today. (Each task
   renders in exactly one section — most-urgent-or-starred bucket wins. That's the dedup.)
4. **Long-term** — target-dated goals. Shared: you and Claude both add and edit here, but
   only *interactively* — see "Files in the vault" for the write-access rule that keeps this
   from becoming a dumping ground for far-dated calendar events.

Bucketing is **driven by due dates** — which is why every task has one; a task with no due
date couldn't be placed in any bucket. The one thing that isn't a due date is the star (`★`):
it doesn't move a task's deadline, it just overrides *which* bucket the task shows in, pulling
it into Today. Take the star off and the task falls back to its due-date bucket, unchanged.

## Tasks

A task is a GitHub-style checkbox. Its metadata lives on an **indented line beneath** it, not
strung along the task line — so the task reads as a plain sentence:

```markdown
- [ ] Prep the client deck
      @20aug · !high · #schoolwork · calendar
      Focus on the pricing slide — they pushed back last time.
- [ ] Email the landlord
      @today · manual
- [ ] Draft the proposal
      @fri · manual · ★
- [x] Read chapter 4
      @fri · #cs101 · ✓18aug
```

(The `★` on "Draft the proposal" pulls it into **Today** even though it's not due until Friday —
its deadline stays Friday.)

| Token | Required? | Meaning |
|---|---|---|
| `@due` | **required** | Due date (`@20aug`, `@today`, `@fri`, ISO). Buckets the task; drives colour/sort. |
| `source` | **required** | Where it came from: `calendar` · `chat` · `manual`. _(default)_ shown as a small muted panel icon; `manual` may be omitted as the implicit case. |
| `✓done` | auto | Stamped when you tick the box. |
| `!priority` | optional | `!high` / `!med` / `!low`. **On-command only** — Claude adds it when you ask, never automatically. Absent = normal. |
| `#type` | optional | A category tag: `#schoolwork`, `#cs101`, `#daily`, whatever you like. |
| `★` | optional | **Focus flag.** Pulls the task into Today regardless of its `@due`; the deadline is untouched. You set/clear it from the panel (see Focus). |
| note | optional | Free prose on a further indented line — context for the task. |
| `every` | optional | Recurrence (`every:week` …), from the existing model. |

**Display ≠ storage.** The block above is the *raw file*. The panel renders it tidy — the
sentence, a small date chip, a faint type tag, a priority dot, a source icon — with no raw
`@`/`#` tokens showing. It stays notes-style, not a Jira grid.

**Focus (`★`).** "Today" used to mean *only* "due at or before today," which made pulling a
task you wanted to work on today — but whose deadline is still days out — impossible without
lying about its due date. The star fixes that: each task row has a star toggle (revealed on
hover), and starring a task writes a `★` onto its metadata line so the panel surfaces it in
Today while its `@due` stays put. Unstarring removes the token and the task falls back to its
due-date bucket. The star is a **you-only affordance** set from the panel — the morning routine
never writes it. Because the panel edit is a *user* action, starring a `longterm.md` goal into
today is allowed under the same interactively-shared rule that bars the unattended routine (see
Files, and DECISIONS.md 2026-09-09 / 2026-09-10).

## Files in the vault

- `brief.md` — the prose summary, regenerated each run. **Claude-owned.**
- `tasks.md` — all dated tasks (Today + This-week buckets). Completed tasks stay here with
  `✓done` until the user clears them by hand — the morning routine never prunes. Clearing
  moves the task to a permanent archive rather than deleting it (decided, not yet built —
  see DECISIONS.md 2026-09-11). **Shared.**
- `longterm.md` — target-dated goals. **Shared**, but *interactively-shared only*: you edit
  it directly, or an interactive Claude Code chat edits it because you asked it to. **The
  unattended 6am morning-brief routine never writes to this file** — it's scoped to
  `brief.md` + `tasks.md`. Long-term is for standing commitments/goals with a deadline
  spanning more than a week (e.g. "take the driving test before 15oct"), not "any task
  whose due date happens to be far away" — a far-dated calendar event stays in `tasks.md`
  (it'll surface in This week once it's close) rather than auto-promoting to Long-term. This
  is a write-access rule, not a classification heuristic: the routine that reads your
  calendar is structurally barred from this file, so there's no judgment call to get wrong.

Three tidy files the panel composes, plus a monthly-sharded `archive/YYYY-MM.md` (decided,
not yet built) that holds tasks the user has cleared. Still no unbounded
`daily/YYYY-MM-DD.md` sprawl — the archive shards by month, not by day.

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
  repaints, but Loaf isn't where you sit and type. Claude fills it; you tick it; the
  long-term list you grow by talking to Claude or editing the file.
- **One device at a time.** Multi-Mac sync of the vault is out of scope.
