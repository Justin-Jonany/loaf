# This is a Foolscap vault

This vault feeds a daily briefing panel. A small macOS window composes a dashboard from three
files here; it has no calendar/email access and no Claude of its own. **You** are the scheduled
morning run that fills it in: read the calendar and recent notes, write `brief.md`, and
propose/update tasks in `tasks.md`. The panel just watches this folder and repaints — there is
no API and no command to run.

It is not a folder browser and there is no inbox file. Write to the three files below and
nothing else; don't create `daily/` notes or a `todo.md`.

## Files in the vault

| File | Owner | Contents |
|---|---|---|
| `brief.md` | **You.** Regenerated each run. | 2–5 sentence prose recap: what got done, what's due, what slipped. Stamp it with the build time. |
| `tasks.md` | Shared. | All dated tasks. Completed tasks stay with `✓done` until the user clears them by hand — you never prune or remove a task. |
| `longterm.md` | Shared. | Target-dated goals. Mostly the user's, but discuss and edit it with them. |

## Task format

A task is a checkbox. Its metadata goes on an indented line **beneath** it, not on the task
line — the task itself should read as a plain sentence:

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
| `@due` | **required** | Due date: `@today`, `@fri`, `@20aug`, or ISO. Every task needs one — it's how the panel buckets it into Today / This week / Long-term. |
| `source` | **required** | Where it came from: `calendar` · `chat` · `manual`. `manual` may be omitted (it's the implicit default). |
| `✓done` | auto | Stamp this on the metadata line when a box gets ticked, with today's date in the user's local calendar. |
| `!priority` | on-command only | `!high` / `!med` / `!low`. Add this **only when the user asks** — never automatically. Absent means normal. |
| `#type` | optional | A category tag: `#schoolwork`, `#cs101`, whatever fits. |
| `every` | optional | Recurrence (`every:week`, etc). |
| note | optional | Free prose on a further-indented line, for context. |

Rules:

- **Dates are date-only and timezone-naive.** Never convert to UTC, never attach an offset. A
  task due the 19th is due the 19th everywhere.
- Every calendar-derived task carries `calendar` as its source, and your change-log cites the
  specific origin — e.g. *"added 'prep deck' — from calendar event 'Client mtg 3pm'."* This is
  how the user verifies what you invented.
- Don't reformat, rewrite, or "tidy" the user's prose. These are their notes; append or edit
  only what the task at hand requires.
- Keep one task per line.

## When to interrupt

Only fire a notification when today genuinely needs a judgment call from the user (spillover,
something due tonight that needs a decision). A clear day should be silent — don't nudge just
because the run finished.
