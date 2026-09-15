# The Loaf task format

Single source of truth for how tasks are written in a Loaf vault's `tasks.md` and
`longterm.md`. Both the `loaf-notes` skill and the `loaf-morning-brief` routine follow
this file — neither restates it. Edit the format **here**; everything else references it.

## Shape: metadata-below

A task is a GitHub-style checkbox. Its metadata lives on an **indented line beneath** it
(6 spaces), so the task line itself reads as a plain sentence. An optional
further-indented note can follow.

```markdown
- [ ] Email the landlord about the lease
      @2026-09-16 · manual
- [ ] Draft the proposal
      @2026-09-19 · chat · !high · #work
      Lead with the pricing section.
- [x] Return library books
      @2026-09-12 · manual · ✓2026-09-13
```

## Tokens

Metadata tokens are `·`-separated.

| Token | Required? | Meaning |
|---|---|---|
| `@<due>` | **required** | Due date. Prefer ISO (`@2026-09-16`); `@today`, `@fri`, `@20aug` also parse. Every task needs one — it's how the panel buckets it into Today / This week / Long-term. |
| `source` | **required** | Where it came from: `calendar` · `chat` · `manual`. `manual` is the implicit default and may be omitted. |
| `!priority` | optional | `!high` / `!med` / `!low`. Absent means normal. |
| `#type` | optional | A freeform category tag, e.g. `#work`, `#health`, `#cs101`. |
| `every` | optional | Recurrence (`every:week`, …). |
| `✓<date>` | on completion | Completion stamp (ISO date). A done task is `- [x]` **and** carries `✓<date>` on its metadata line. |
| note | optional | Free prose on a further-indented line, for context. |

## Rules

- **Dates are date-only and timezone-naive.** Never convert to UTC, never attach an
  offset. A task due the 19th is due the 19th everywhere.
- **Every task needs `@due`** — without one it can't appear in the panel.
- **One task per line** (the checkbox line); metadata and notes go on the indented lines
  beneath it.
- **Never reformat or reorder lines you didn't add.** Preserve the user's own prose and
  spacing; touch only what the task at hand requires.
- Marking done = flip `- [ ]` to `- [x]` **and** append `✓<ISO date>`; never delete the
  task (removal is a user-only action).

Consumer-specific behaviour — which `source` to write, whether priority may be set
automatically, calendar tiering, add-only constraints — lives in each skill, not here.
