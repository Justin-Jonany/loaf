# Decisions

A running log of the decisions that shaped Loaf — newest first. Each entry records what
was decided, why, and what it replaced, so a choice (and any later reversal) has a home that
ROADMAP (the plan) and CHANGELOG (shipped history) don't provide.

## 2026-09-18 — Cross-run de-dup spans the archive, bounded by the due-date window

**Decided:** before adding a calendar-derived task, the morning routine now checks the
permanent archive (`archive/YYYY-MM.md` — the current month's shard and the previous
month's) in addition to `tasks.md`. A matching archived entry suppresses the addition
outright: nothing is added, and nothing is reported under "What changed." The match is
bounded to the run's today-through-today+7 window — only an archived entry whose `@due`
falls inside that window can suppress. The archive stays read-only to the routine: it never
un-archives, re-dates, or copies an entry back into `tasks.md`.

**Why:** the 2026-09-12 de-dup matched against `tasks.md` alone, but archiving is precisely
the act of *removing* a task from `tasks.md`. Combined with the add-only rule (DECISIONS.md
2026-09-11), which makes archiving the user's only way to say "I'm done with this," the two
rules composed into a bug: a task finished early and cleared became invisible to the check
meant to stop it being re-added, so the routine resurrected it every morning until the event
date passed. Seen in a real vault with "Submit REC 101 Case #1" (archived 09-14, event
09-16) — the user clears it, and tomorrow it is back. Reading the archive closes the loop
by making "cleared" mean the same thing to the routine that it means to the user.

The due-date bound is the non-obvious half, and it is load-bearing. Matching on title alone
against months of archived history would silently swallow legitimately new events: "Dentist
appointment" and "Coffee chat with Hunter" recur as distinct one-offs with new dates, and an
entry archived in August would suppress September's for good — a false negative the user
would never see, which is a worse failure than the duplicate it prevents. Keying on event +
date makes "same event" mean same event, not same words. Two shards rather than a date-range
scan because the shards are monthly and small; a calendar-derived task cannot have been
archived more than seven days before its event, so the pair is comfortably sufficient.

**Not decided:** task identity remains fuzzy prose matching. The exact fix is stamping the
calendar event id onto the task, but `TaskBlock.applyMetadata` ignores unrecognized tokens
on parse and drops them on render, so any such token is destroyed on the next archive or
checkbox write-back — it needs a real `LoafCore` field, not a prompt change. Deferred until
prose matching demonstrably misses.

## 2026-09-15 — Task format extracted to a single source of truth; brief becomes an insight layer

**Decided:** the task format (the metadata-below shape, its tokens, its rules) is now
authored once, in a new repo-root `TASK-FORMAT.md`. The vault's `templates/CLAUDE.md`, the
morning-brief SKILL, and the `loaf-notes` SKILL each used to restate the format in full and
had drifted out of sync — most visibly, the `★` focus-flag token existed in only one of the
three copies. All three now reference `TASK-FORMAT.md` instead of restating it: the
morning-brief routine injects it into its prompt (`run.sh`), and both skills read it via a
new `contract` pointer in `~/.config/loaf/config.toml`, written by a new
`scripts/install.sh` (which also copies both skills into `~/.claude/skills/`, replacing
the old manual `cp -R` step). A vault's own `CLAUDE.md` is demoted to personal
preferences/context only — tone, priorities, the people in the user's life — and never
carries the format, so it needs no edits when the format changes.

Alongside this, the morning brief's spec changed from a "2–5 sentence recap" to an
**insight layer**: it now surfaces only what the task list can't show on its own —
spillover, an unusually heavy or light day, a collision, a resolved ambiguity. One phrase
is a valid brief; four sentences is a hard cap; it never pads when there's nothing to note.
The stale `★` focus-flag token is dropped from the format entirely. A new `loaf-brief`
skill wraps `routines/morning-brief/run.sh --force` so the user can rebuild today's brief
on demand — e.g. when the 6am run didn't fire.

**Why:** three hand-maintained copies of the same format is exactly the shape that drifts —
this was caught only because the `★` token happened to exist in just one of them. A single
authored file that everything else references removes the possibility of drift by
construction, and demoting the vault's `CLAUDE.md` to personal-only means adding a token or
changing a rule is now a one-file change instead of a three-file hunt. The brief's rewrite
from "recap" to "insight layer" follows the same instinct: a recap duplicates what the task
list already shows, while an insight layer only earns its space when it says something the
list can't.

## 2026-09-14 — Today is drag-reorderable; This week/Long-term are not

**Decided:** dragging a row within the dashboard's Today section reorders it by physically
moving the task's block (checkbox line + metadata line + optional note line) within its
source file, verbatim — the drag handle is the same `.focus-toggle` element the
drag-to-Today gesture already uses, distinguished by whether the drag started AND ended in
Today (`fromSection === 'today'` on both ends, not `payload.focused` — a task can sit in
Today from an overdue/due-today `@due` with no `today` token at all). This week and
Long-term stay sorted by due date and are not reorderable. Because Today composes
tasks.md-members before longterm.md-members, a drag that would interleave the two files has
no representable on-disk order — such a drop (or a drop onto empty Today space, or onto the
row's own position) is a safe no-op, never a write.

**Why:** reordering only means something where the user actually curates order by hand;
This week/Long-term are already meaningfully ordered by due date, so adding drag-reorder
there would just let a drag silently fight that ordering on the next render. Moving the
block's raw lines rather than re-rendering it (unlike the checkbox/focus toggles) keeps a
reorder from ever reformatting a task the user didn't touch.

## 2026-09-13 — Repo goes public (supersedes 2026-08-15 "private GitHub")

**Decided:** the repository is now public. The rest of the 2026-08-15 workflow stands — no
direct commits to `main`, each slice on a feature branch behind a reviewed PR — only the
visibility changes.

**Why:** it's stable enough to show, and being public is the point of putting it on a résumé.
Public also unlocks GitHub's branch protection, which free private repos don't get (the reason
the local `.githooks/` guards exist), so the server-side guard the old entry lacked is now
available if wanted.

## 2026-09-13 — Calendar tiering keys on recurrence (`recurringEventId`), not on whether an event has an action item

**Decided:** the morning-brief routine's calendar tiering (`routines/morning-brief/SKILL.md`
→ "Calendar tiering") now decides task-vs-context by whether the event carries a
`recurringEventId`, not by whether it appears to have an action item. An event that is one
instance of a recurring series (a class, a standing sync, a focus/study block) is **never**
a task, however action-item-shaped its description reads — it's surfaced as brief context
only. An event with **no** `recurringEventId` — a seminar, a 1:1/coffee chat, an interview,
an appointment, a graded deliverable — is added as a **task**, `source: calendar`, dated
with the event's own date; a description now only *enriches* that task's note, it no longer
decides whether a task gets created at all. A one-off is downgraded to prose-only in the
rare case it's clearly a personal non-obligation with no counterparty and nothing to do (a
lunch block, a nap); the routine still adds when unsure.

**Why:** verified against the user's live Google Calendar feed — every event belonging to a
recurring series is tagged with `recurringEventId` by `list_events`, and a series is expanded
into one instance per occurrence, so classes, standing syncs, and focus blocks all carry it
while one-off meetings, interviews, and deliverables don't. The old rule ("does this look
like it has a real action item") asked the routine to *infer* recurrence and importance from
a description, which is exactly backwards when the calendar already states recurrence as a
fact — a plain "Coffee chat with a friend" with no description used to read as "minor, no real
follow-up" and get skipped, when it's actually a one-off meeting worth a task regardless of
what its description says. Keying on `recurringEventId` removes that inference entirely: no
wider read window is needed, and a bare one-off (no description, no attendees) still gets
picked up correctly rather than accidentally downgraded to prose for lacking descriptive
detail.

**Known gap, accepted for v1:** `recurringEventId` is set by the calendar's own recurrence
feature. A "recurring" commitment entered as several separate manual events (no shared
series) carries no `recurringEventId` and looks like a one-off under this rule — it becomes
a task each time it appears. Acceptable for now: it costs a few extra (accurate, just
redundant) tasks rather than silently hiding a real one-off as context.

**References:** builds on the 2026-09-12 "7-day lookahead + dedup" decision below — the
window and dedup behavior are unchanged; only the task-vs-context call within that window
changes.

## 2026-09-12 — Morning routine looks 7 days ahead and de-dupes calendar tasks across runs

**Decided:** the morning-brief routine (`routines/morning-brief/SKILL.md`) no longer reads
the calendar for today's date only — it reads a rolling window from today through today+7,
inclusive, in both the live path and the dry-run/fixture path (the fixture is filtered to
the same window by each event's `start` date). A future calendar-derived task is due-dated
with the event's own date, ISO `YYYY-MM-DD`, not `@today` and not the day before. Because
the same event can now surface across several mornings' windows, the routine checks
`tasks.md` before adding — matching on the event (title + date), not exact wording — and
adds nothing if it already captured that event. If a captured event has been rescheduled,
the routine edits that task's existing `@due` to the new date instead of adding a second
one (the one calendar case where it changes an existing `@due`) and cites the reschedule in
`brief.md`'s "What changed." A cancelled event can't be removed (still add-only) — the
routine leaves the task and notes the cancellation in `brief.md` so the user can clear it
by hand.

**Why:** today-only gave zero advance visibility — an event three days out never became a
task until the morning it happened, which is exactly the gap DECISIONS.md 2026-09-09
(ticket C1) flagged when it noted a far-dated calendar event "isn't promoted to Long-term
... it stays in `tasks.md`" and (per `SKILL.md`) "surfaces in This-week as it nears" — that
only works if something actually looks far enough ahead to put it there. The cost of
looking ahead is that add-only means a task, once written, can't be retracted by the
routine if the event turns out to be routine-classified wrong or gets cancelled later; a
7-day window (rather than, say, 30) keeps the lookahead inside the range where events are
mostly settled, and rescheduling edits the existing task rather than piling up duplicates
as the same event drifts across a few mornings' windows.

## 2026-09-12 — Completed tasks stay visible until the user archives them

**Decided:** completed tasks stay visible on the panel indefinitely — struck-through, in
their `@due` bucket — and only the user's archive action removes a row from the panel. This
reverses the 2026-09-09 decision (and its 6am-rollover fall-off) that a completed task
lingered only until the next rollover.

**Why:** the markdown files are the source of truth and the user, not the app, owns removal.
A done task silently leaving the panel the next morning read as data loss ("a bunch of tasks
are gone") even though the file kept it. Making the panel show everything in the file until
the user archives it makes the panel a faithful mirror of `tasks.md` and puts removal
entirely in the user's hands (archiving). Cost: completed rows accumulate on the panel over
time (an old done overdue task sits struck-through in Today) until archived — accepted,
archiving is the broom.

## 2026-09-11 — The panel drops source icons and the `#type` tag; `#type` stays parsed

**Decided:** `DashboardTaskRenderer` no longer emits a source-origin icon (📅 calendar, 💬
chat, ✎ manual) or a `#type` category tag for a task row — the rendered fragment is now just
the sentence, the due chip, and the priority dot. `TaskBlock`'s parsing and round-trip of
`#type` (and of `source`) are untouched: the value is still read from and written back to
`tasks.md`/`longterm.md`, just no longer displayed.

**Why:** both were low-value chrome that cluttered a narrow panel without earning the space —
the source is rarely worth knowing at a glance, and `#type` reads as noise next to the due
chip and priority dot that actually drive triage. Keeping the storage format untouched means
this is purely a display change, reversible without a migration.

## 2026-09-11 — Overdue uses the shared due-chip convention, consistently across themes

**Decided:** `.due-over` drops its `box-shadow: inset 2px 0 0 var(--due-over)` left
edge-marker and now shares the exact chip shape `.due-soon` already uses — red text plus a
tinted `--due-over-bg` background, no separate treatment. Console's own `.due-over` override
(`background: none; box-shadow: none; font-weight: 700`) and its `.due-over::before { content:
"! " }` marker are deleted outright, so console falls through to base.css's rule and picks up
the same red-tinted chip (and its own `--due-over`/`--due-over-bg` tokens) as every other
theme.

**Why:** the edge-marker and console's bespoke "! " prefix were two more one-off severity
treatments than the panel needed — overdue reads clearly enough as red text on a red-tinted
pill, the same shape already used for "due soon," so every theme now agrees on one convention
instead of each theme improvising its own.

## 2026-09-11 — Completed tasks keep their position instead of sorting to the bottom

**Decided:** `DashboardComposer.compose` now returns each bucket (Today/This week/Long-term)
in parse order; a task checked off no longer moves within its section. This reverses the
2026-09-09 "sorts to the bottom of that section" call (ROADMAP B6) — the `sortedOpenFirst`
helper that implemented it is removed. A completed-today row still lingers until the 6am
rollover (`isEligible`, unchanged) and still renders struck-through/dimmed; it simply doesn't
jump to the end of the list to get there.

**Why:** reordering a row the instant you check it works against the "glanceable daily
surface" the panel is meant to be — a task jumping position mid-scan is more disruptive than
useful, and parse order (which the human controls by how they write the file) is a perfectly
good order to leave a row in.

## 2026-09-11 — Overdue severity, theme templating, and lifecycle sub-decisions

**Context:** A review pass (four investigation lenses over the panel's visuals and the
still-unimplemented redesign below) surfaced a set of concrete decisions and resolved the
open sub-choice left in that entry. Two findings are latent bugs, not just polish: the
dashboard due chip never emits an urgency class, so the themes' `.due-soon`/`.due-over`
styling is dead on the panel; and the `card`/`console` themes don't style the dashboard at
all — every dashboard-only class falls back to browser defaults when they're selected.

**Decided:**

- **Overdue reads as more severe on the dashboard; due-today does not.** Wire the existing
  urgency logic into `DashboardTaskRenderer` (a new `TaskBlock.urgency`, mirroring
  `TaskLine`'s, with `soon_within_days` threaded from config). A task due before today gets
  a restrained red treatment; **due-today maps to the softer `due-soon`, not red** —
  reddening the common case would make every day's list read as an emergency. Severity is
  scoped to the `.due-over`/`.due-soon` *class selectors*, never the `--due-over` CSS
  variable (which is shared by the priority dot, focus control, and freshness badge). No
  "days late" count in the chip — the panel is narrow; the color/edge-marker carries it.

- **Themes become a shared base plus a palette.** Structure moves to a single
  `Resources/themes/base.css` written against a documented token contract; each theme file
  (`frosted`/`card`/`console`) shrinks to a `:root` palette (plus any signature extras and
  its own optional dark/contrast blocks). `HTMLPage.wrap` concatenates base + theme. This
  makes the ROADMAP promise ("a new theme is one CSS file, no Swift") true and fixes
  `card`/`console` silently leaving the dashboard unstyled. Dead selectors (`.mermaid`,
  `.task .box .tick`) are dropped. Migrate `frosted` first and diff the composed output to
  prove the extraction is inert before it becomes the only path.

- **Live theme switching.** The selected theme name is read once at launch; make the app
  re-read `config`'s `theme` on its existing repaint triggers and add a menu-bar picker
  that writes the `theme` key, so themes swap without a relaunch (the CSS already
  hot-reloads on repaint).

- **Fix `saveSharedFile` swallowing write failures (`main.swift`).** It currently logs and
  returns on a failed atomic write while the caller repaints as if it succeeded — a latent
  data-safety bug today (a failed tick/focus looks applied), and the prerequisite for the
  archive's archive-first-then-strip crash-safety.

Resolving the open sub-choices from the entry below:

- **The on-disk placement token is renamed `★` → `today`.** Since the star glyph is retired
  from the UI, a bare `★` in `tasks.md` would correspond to nothing visible; `today` reads
  honestly in the plain-text file. Existing `★` lines get a one-time migration. The `focus`
  boolean and its conflict-guarded write-back are unchanged; only the rendered token
  spelling changes.

- **Restore reopens the task.** `restoring` clears `✓done`/`isDone` so a restored task
  returns as an active item — otherwise it would land back in `tasks.md` but be filtered out
  of every dashboard bucket (done-and-not-today), an invisible "restore."

- **Archiving is no longer gated on done** (amends the archiving bullets in the 2026-09-11
  "Task lifecycle redesign" entry below, which described it as clearing a *done* task).
  Any task can be archived, not only a completed one — the archived record preserves
  whatever done-state it had at that moment (a not-done task archives with no `✓done`; a
  done task keeps its `✓done`), alongside the `archived:` stamp. Restore is unaffected: it
  still reopens the task per the resolution just above.

- **Manual drag-reorder, if built, is scoped to the Today section only**, stored as a
  gap-numbered `order:` field. This-week/Long-term stay sorted by `@due` (a manual order
  there would fight the deadline sort). Deferred — a later slice, after drag-to-Today.

**Why:** the visuals work is mostly connecting logic and CSS that already exist, and it
directly answers the "make overdue severe" and "several easily-swappable themes" asks while
keeping the panel calm — red stays rare and meaningful, and structure stops being copied per
theme. The lifecycle resolutions favor the plain-text-you-own principle (a legible on-disk
token, no silently-lost data) over saving a trivial migration.

**References:** resolves the "Open sub-choice" and fills in the implementation slices of the
2026-09-11 "Task lifecycle redesign" entry below.

## 2026-09-11 — Task lifecycle redesign: add-only routine, human-owned removal, permanent archive, sticky drag-to-Today

**Context:** dogfooding surfaced that the unattended morning routine silently deleted a
completed task (the >7-day prune, below), and that the checkout living under `~/Desktop`
(a macOS TCC-protected folder) blocked the launchd morning-brief agent from executing
`run.sh` at all ("Operation not permitted"). Both pushed a rethink of *who is allowed to
mutate the task list, and when*. The decisions below reshape the daily loop around one
principle: **automation may add or relocate, but only the user removes, and only on an
explicit instruction.**

**Decided:**

- **Removal is user-instructed only.** Claude is *capable* of removing a task, but must
  not remove one unless the user says so in that session (interactive chat). The
  unattended routine never removes anything. This replaces the rule that the routine
  auto-prunes completed tasks — see the reversal note below.

- **The unattended routine is add-only on `tasks.md` (fork A).** It still creates tasks
  from the calendar, because that needs *judgment* a script can't supply: the user's
  calendar is full of recurring class blocks that must **not** become todos but should
  still be *seen*. Tiering the routine applies:
  - routine/recurring blocks (classes) → never a task; surfaced as **brief** context;
  - an important event with a real action item → a **task** (`source: calendar`);
  - minor-but-worth-mentioning → **brief** prose, no task.
  The routine also writes `brief.md` + its "what changed" changelog. It does **not** prune
  and does **not** set Today-placement (that's now a human gesture). Its only `tasks.md`
  write is adding calendar-derived tasks.

- **No 7-day auto-delete; the archive is permanent and append-only.** Completed tasks are
  never destroyed by automation. When the user clears a done task it moves to an archive
  and stays there indefinitely (a permanent completion log the retrospective can read).
  A completed task not yet cleared simply stays in `tasks.md` (the panel already drops
  done tasks from the *active* view on repaint, which is why they "disappear" visually
  while the line persists — the source of today's confusion).

- **Archive storage is sharded markdown, not a database.** The archive lives as
  `archive/YYYY-MM.md` (one file per month) inside the vault — preserving the
  plain-text-you-own, greppable, git-able property that is the whole point of the vault
  (`tasks.md`/`longterm.md`/`brief.md` stay markdown, always). Monthly sharding solves the
  unbounded-growth of a keep-forever log; the archive viewer loads only the month in view.
  A local SQLite store was considered and **deferred**: it's only justified by a concrete
  *query* need (completion velocity, "what did I finish in August"). If that arrives, the
  correct shape is markdown-as-source-of-truth with SQLite as a rebuildable *index* over
  it — never moving the data itself out of plain text.

- **Archive mechanics.** Clearing a done task stamps an `archived:<ISO-8601 datetime>`
  field (the precise "when it left the list", with time — `✓done` stays a date-only stamp
  in `tasks.md` so that file's format and round-trip stay untouched) and moves the block to
  the month shard. New `TaskBlock` mutations mirror the existing `toggling`/`settingFocus`
  spine (parse-at-line, conflict-guard a stale click, re-render, atomic write): `archiving`
  and `restoring`. Two-file writes append to the archive **first**, then strip from
  `tasks.md`, so a crash between them duplicates (recoverable) rather than loses.
  **Restore** is add-side: available from an archive viewer's per-row button and to
  interactive Claude on request, but never to the unattended routine (no surprise
  resurrections — same boundary that keeps it out of `longterm.md`). **Permanent delete**
  is human-only and its UI is deferred (keep-forever is the default; nothing forces a
  destroy path yet).

- **Today-placement is a sticky drag, replacing the `★` focus flag (supersedes the
  2026-09-10 B7 entry).** A task is pulled into Today by **dragging** it into the Today
  section, not by starring. It is **sticky**: it stays in Today across days until the user
  completes it or drags it back out — it does not auto-expire and never needs re-dragging.
  `@due` is never touched (the deadline stays the source of truth for urgency/sort — the
  reason B7 rejected rewriting `@due` still holds). The data stays the boolean `focus`
  field and the conflict-guarded write-back (`settingFocus`); what changes is (a) the
  trigger becomes drag instead of a per-row star toggle, (b) the `★` glyph is retired and
  the panel shows **no** placement badge — a task's mere presence in the Today section is
  the only indication (keeps priority, which is `!high/!med/!low`, visually distinct from
  placement, which a star wrongly connoted as importance). A keyboard/click affordance is
  kept alongside drag for the X2 accessibility contract.

- **Operational:** the checkout was moved out of the TCC-protected `~/Desktop` to
  `~/Projects/loaf`, and both paths in `com.loaf.morning-brief.plist` (ProgramArgs
  + WorkingDirectory) were repointed and the launchd agent reloaded (last exit 126 → 0).
  Rule of thumb recorded: never keep the checkout under `~/Desktop`/`~/Documents`/
  `~/Downloads` (launchd/TCC can't reach it), and always `rm -rf .build` after moving a
  Swift checkout — the module cache bakes in absolute paths and is not relocatable.

**Why:** the through-line is *trust*. The one actor that runs with no live human
instruction (the morning routine) is reduced to add-and-describe, so it structurally
cannot surprise-delete or surprise-move the user's tasks; everything destructive or
re-arranging is either deterministic (the panel buckets by `@due`) or an explicit human
act. Keep-forever + plain-text archive means no data is ever silently lost and history
stays owned and greppable. Sticky drag-placement matches how the user actually works
("I'll focus on this until it's done") without overloading a star that read as priority.

**Reverses:** the "morning routine prunes `✓done` tasks older than 7 days" behavior
(`routines/morning-brief/SKILL.md` "Pruning", `DESIGN.md` → "Files in the vault", and the
fixtures' `CLAUDE.md` wording) — the routine no longer deletes. **Supersedes** the
2026-09-10 B7 decision (the `★` focus flag as a starred per-row toggle): the mechanism
becomes a sticky drag with no visible token, though the underlying `focus` field and
write-back path are retained.

**Status:** decided this session; not yet implemented. Suggested implementation slices:
(a) remove the routine prune (SKILL/DESIGN/fixtures); (b) `archived:` field + month-shard
archive file + `archiving`/`restoring` on `TaskBlock` with selftests; (c) panel clear
button + archive viewer (restore / deferred delete); (d) drag-to-Today interaction + `★`
glyph retirement. Open sub-choice: the markdown token spelling for a pulled task, if any is
kept on disk beyond the existing `focus` boolean's rendering.

## 2026-09-10 — Panel UI polish: the panel owns section chrome, custom checkbox, human dates

**Decided:** A pass of visual fixes to the composed dashboard, driven by dogfooding the real
panel:

- **The panel owns the section labels; the brief content must not repeat them.** The routine
  was told (SKILL.md) to open `brief.md` with a `# Brief` heading, which the panel then rendered
  *below* its own "Brief" section title — two "Brief" headings stacked. The routine no longer
  writes that heading (brief.md is the stamp line + prose directly), and `DashboardRenderer`
  additionally strips a redundant leading "Brief" heading defensively, so an existing brief that
  still carries one renders cleanly. Same principle as Today/This-week/Long-term: those labels
  live in the viewer, never in the files.
- **Heading hierarchy.** Every heading rendered at one weight (15px/600), so an in-brief
  sub-heading ("What changed") shouted as loud as a top-level section. Section titles stay
  dominant; markdown headings *inside* the brief are demoted to a small muted sub-label.
- **Custom checkbox.** The raw WebKit `<input type=checkbox>` (a bright, heavy square) clashed
  with the translucent theme and sat misaligned above the task text. Restyled via
  `appearance: none` to a subtle rounded control in the theme's muted palette — a visual set
  with the `★` focus toggle (B7) — and aligned to the first text line. It stays a real `<input>`
  so the X2 VoiceOver/ARIA contract is untouched.
- **Human due dates.** The chip showed the raw ISO date (`2026-09-10`). It now reads
  `Today` / `Tomorrow` / `Yesterday`, else `MMM d` (same year) or `MMM d, yyyy`, computed
  against the panel's rollover-aware today; the exact ISO date remains as the chip's `title`
  tooltip. (Advances the "locale-aware date display" good-first-issue in ROADMAP.)

**Why:** these are the first things a real user notices, and none change the data model or the
files on disk — they're display-layer only (CSS + the render path), consistent with DESIGN.md's
"Display ≠ storage."

**Status:** settled; implemented in one UI-polish PR.

## 2026-09-10 — "Today" is curated: a `★` focus flag pulls a task in, decoupled from `@due` (ticket B7)

**Decided:** A task can be pulled into the **Today** section by *starring* it, independent of
its due date. The star is stored as a `★` token on the task's metadata line
(`@fri · manual · ★`). `DashboardComposer` buckets a task into Today when it is `@due` at or
before today **or** carries `★`; a starred task keeps its real `@due` and simply renders in
Today instead of its due-date bucket (This week / Long-term). Unstarring removes the token and
the task falls back to that bucket. The star is set/cleared from the panel via a per-row toggle,
written through the existing conflict-guarded write-back path (ticket X1) — the same way a
checkbox tick is.

**Why:** dogfooding against the real vault surfaced that "Today = `@due` ≤ today" is too rigid —
there was no way to say "I want to work on this today" for a task whose deadline is legitimately
a few days out, short of rewriting its `@due` to today and destroying the real deadline.
Considered exactly that (make the pull action rewrite `@due` to today): rejected because it
conflates *when a thing is due* with *when I choose to do it*, loses the true deadline, and
leaves "send it back to the backlog" with no original date to restore. A separate flag keeps the
two orthogonal — the deadline stays the source of truth for urgency/colour/sort, the star only
overrides section placement.

**Why `★` and not `@today`:** `@` is already the **due-date** prefix, so `@today` parses today as
a *due date* (`TaskBlock` → `DateToken`), not a focus flag — it can't do double duty. `!` and `#`
are taken by priority and type. A bare `★` token is unused, reads unambiguously as "starred /
focused," and stays out of the tidy render's `@`/`#`/`!` token space. It renders as a small star
affordance in the panel, never as raw text.

**Consequence:** `TaskBlock` gains a `focus: Bool` field (parsed from `★`, rendered in fixed
field order so round-trips stay stable) and a `settingFocus(…)` write-back mutator mirroring
`toggling(…)`. `DashboardComposer` bucketing gains the star-override rule. The panel gains a
star toggle per row and a `focusTask` message handler alongside `toggleTask`. Consistent with
the 2026-09-09 rule: starring is a *user* write, so a `longterm.md` goal may be starred into
Today from the panel even though the unattended routine still never writes either file's star.
Tracked as ticket **B7**.

**Status:** settled. Implemented under ticket B7 (ROADMAP.md → Epic B).

## 2026-09-09 — Long-term is interactively-shared only; the unattended morning routine never writes it (ticket C1)

**Decided:** `longterm.md` can be edited by the user directly or by an *interactive* Claude
Code chat session the user is driving, but the unattended 6am morning-brief routine
(`routines/morning-brief/`) is scoped to `brief.md` + `tasks.md` only and must never write
`longterm.md`. Long-term is for standing commitments/goals with a deadline spanning more than
a week — not "any task whose `@due` happens to be far away." A far-dated calendar event stays
in `tasks.md`; it isn't promoted to Long-term just because its due date is distant.

**Why:** The bucketing worry that prompted this ("a calendar event two months out shouldn't
land in Long-term") turned out not to be a `DashboardComposer` bug — Long-term is already its
own file, not a due-distance bucket computed from `tasks.md` (`Dashboard.swift`; confirmed by
the `LoafSelftest` case asserting `longterm.md` entries land in Long-term "regardless of
how far out `@due` is"). The actual gap was `routines/morning-brief/SKILL.md`, which gave the
*unattended* routine permission to add to `longterm.md` on its own judgment ("only add an
entry here if a calendar event or note clearly implies a new target-dated goal") — a vague
heuristic with only a far due date as its cue, and broader than ticket C1's own stated scope
(brief.md + tasks.md). Considered classification approaches instead (an explicit `#goal`
marker, a `source`-based exclusion rule) but rejected them: `longterm.md` vs. `tasks.md` is
already the marker — the file boundary — so a second in-band marker would be redundant. Fixing
*who can write the file* removes the judgment call entirely rather than trying to make the
judgment call more precise: the pipeline that reads the calendar is structurally barred from
this file, so it can't misclassify what it never touches.

**Consequence:** `routines/morning-brief/SKILL.md` must be corrected to drop its
longterm.md-writing permission (currently lines 36–38) before the routine is trusted against a
real vault — tracked as part of ticket C1, which never scoped longterm.md writes in the first
place. `dry_run.sh all`'s fixtures should include a case with a far-`@due` calendar event and
assert `longterm.md` is untouched by the run.

**Status:** settled. Ticket C1's Solution/Tests updated in ROADMAP.md; `SKILL.md` fix is
implementation work under C1, done before the first live run against the real vault.

## 2026-09-09 — A malformed `.routine-signal.md` is treated as a failure, not silence (ticket D2)

**Decided:** `RoutineSignal.parse` distinguishes three outcomes, not two: `nil` for an
absent/blank file (the clear-day state), a typed `.needsDecision`/`.failed` value for
well-formed content, and a third `.malformed` status for content that's present but
doesn't carry a recognized `status:` line. `SignalNudge.decide` folds `.malformed` into
the same failure nudge as `status: failed` — a distinct, louder notification — rather than
either dropping it silently (as if `nil`) or crashing/ignoring it.

**Why:** the ticket's problem statement is explicit that the app must stay silent on a
clear day *and* be loud on failure (DESIGN.md → Trust: "Failure is loud"); a signal file
that exists but fails to parse (a half-written file from an interrupted run, a future
schema change this parser doesn't know yet, ...) is closer in spirit to "the routine
broke" than to "nothing to report." Silently swallowing it would recreate exactly the
failure mode DESIGN.md calls out — a broken run looking like a clear day instead of
nudging the user.

**Also decided:** the failure nudge is made "louder" than the ordinary decision nudge via
`UNNotificationInterruptionLevel.timeSensitive` (can pierce Focus filtering that would hold
back a `.active` notification) plus `UNNotificationSound.defaultCritical`, not via the
`critical-alerts` entitlement — Loaf is an unsigned, direct-distribution app (ROADMAP.md
→ Hazards → Distribution) that can't carry that entitlement, so `.defaultCritical` degrades
gracefully to a louder default sound rather than a true critical alert.

**Status:** shipped.

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
and `ConflictGuard` (`LoafCore`) know nothing about how the caller informs the user.

**Status:** shipped. Not a reversal of anything; extends the hazard already logged in
ROADMAP.md → Hazards → "Write conflicts on shared files."

## 2026-09-09 — Completed tasks linger in the panel until the 6am rollover (ticket B6)

**Decided:** A task you complete **today** stays visible in the panel — struck-through, sorted
to the bottom of its own section, open items first — until the 6am rollover, then drops. It
applies to every section, **Long-term included**. Layout is *in place* (the task stays in its
`@due`-based section); rejected an alternative "Done today" collector group as more disruptive
to the one-task-one-bucket model.

**Why:** B1's original rule showed only *unchecked* tasks, so ticking a box made the row vanish
instantly — no "I did it" feedback and no in-panel trace of the day's progress. Lingering
completions give the day visible momentum without a new store: the filter widens from
"unchecked" to "unchecked or (`isDone` and `done == today`)", and B5's 6am rollover makes them
fall off for free (yesterday's completions stop matching `done == today`) — no timer, no
cleanup pass. An undated hand-edited `[x]` does not show (can't be dated to "today").

**Supersedes:** DESIGN.md's earlier "the brief is the *only* place finished work shows up, since
done tasks drop out of the lists below." The brief still owns the *cross-day* recap; the panel
now also shows *today's* completions until rollover.

**Status:** shipped (ticket B6).

## 2026-08-23 — Morning routine signal: sidecar file `.routine-signal.md` (settled)

**Decided:** the routine's "needs a decision" / "failed" signal is a small dotfile,
`.routine-signal.md`, at the vault root — `status: needs-decision|failed`, `at:` (ISO 8601,
same shape as the `brief.md` build stamp), `reason:`, and (for a decision) `questions:`.
Absence of the file is the "clear day, nothing to see" state. **This is the final location**
(updated 2026-09-09), not a marker line in `brief.md`.

**Why this shape:** it fires `VaultWatcher`'s existing `.md`-extension filter with no watcher
code changes (a dotfile is still `*.md`), while `Vault.notePaths()` already skips dotfiles, so
it never shows up as a note in the panel. It also keeps `brief.md` pure human-readable prose
rather than mixing in a machine-parsed control line.

**Resolution (2026-09-09):** ROADMAP.md's "Open decisions" had left *where this signal lives*
— this sidecar vs. a marker line in `brief.md` — pending ticket **D2**. Settled in favour of
the sidecar C1 already ships: it needed no changes to the watcher and kept `brief.md` prose,
and nothing in D2's design argued for moving it. This **unblocks D2** (the app-side consumer),
which now reads `.routine-signal.md`.

**Status:** settled — the sidecar is the signal location; D2 consumes it.

## 2026-08-18 — Product direction: Loaf is a daily-briefing panel

**Decided:** Loaf is a **daily briefing panel**, not a generic markdown note widget. Each
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

**Supersedes:** the ROADMAP framing that treated Loaf as a general markdown note widget
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

**Superseded** (visibility only) by 2026-09-13 "Repo goes public" — the PR-per-slice and
clean-`main` rules still hold.

## 2026-08-15 — Markdown rendering: depend on swift-markdown

**Decided:** Use `swift-markdown` (pinned 0.8.0) to parse CommonMark+GFM to an AST, rendered to
HTML in `LoafCore`; task-list items are re-parsed through `TaskLine` so `due:`/`done:`/
`every:` semantics survive.

**Why:** Correct markdown without hand-rolling a parser; it still builds with plain
`swift build` (no Xcode), consistent with the project's "no Xcode required" stance.

## 2026-08-15 — Config: hand-rolled reader, no TOML dependency

**Decided:** Read the documented subset of `config.toml` with a small key/value reader; add no
TOML library.

**Why:** Keep the dependency surface minimal; full TOML fidelity is not needed.

## 2026-08-15 — Architecture: hexagonal core boundary, enforced

**Decided:** `LoafCore` imports no UI frameworks (AppKit/Cocoa/UIKit/SwiftUI/WebKit);
`scripts/check-core-boundary.sh` fails CI if it does.

**Why:** Keep the domain logic GUI-free and self-testable, and stop the boundary from rotting
silently.

---

**Still open** (tracked in [ROADMAP.md](ROADMAP.md) → Open decisions): the app name (`loaf`
is a placeholder), Gatekeeper/notarization vs. documenting the workaround, and preview-vs-source
on open.
