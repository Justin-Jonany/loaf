---
name: loaf-notes
description: Add or edit tasks and long-term goals in the user's Loaf vault (~/Notes) from any directory. Use when the user asks to add/change/complete a task, jot a to-do, add a long-term goal, or "put X in my loaf notes / my notes / my brief". Knows the vault location and the metadata-below task format so edits parse correctly.
user-invocable: true
allowed-tools:
  - Read
  - Edit
  - Write
  - Bash(cat *)
  - Bash(ls *)
  - Bash(printenv *)
---

# Editing the Loaf vault

Loaf is a daily-briefing panel that reads a small set of markdown files from a **vault**
folder. This skill is how, from *any* session in *any* directory, you make correct edits to
those files at the user's request. The panel watches the files and repaints on save.

## Find the vault

Resolve the vault root in this order (first that exists wins):

1. `$LOAF_VAULT` if set — `printenv LOAF_VAULT`.
2. The `vault = "..."` line in `~/.config/loaf/config.toml` (tilde is expanded).
3. Default: `~/Notes`.

Currently this is **`~/Notes`**. Operate on files *inside the resolved vault* — never guess a
path elsewhere.

## The three files (edit the right one)

- **`tasks.md`** — all dated tasks (the Today + This-week sections of the panel). This is where
  most requests land: "add a task", "mark X done", "change the due date". Shared with the user
  and the morning routine — don't reformat lines you didn't add.
- **`longterm.md`** — standing goals with a deadline more than a week out. You **may** edit this
  in an interactive session like this one (that's the whole point — the unattended 6am routine
  is barred from it, but a user-driven chat is not). Add a goal here only when it's a real
  long-term commitment, not just a far-off task.
- **`brief.md`** — a prose recap the morning routine writes. **Claude-owned; do not hand-edit**
  unless the user explicitly asks.

If a target file doesn't exist yet (e.g. no `tasks.md`), create it with a `# Tasks` /
`# Long-term` heading and the first entry.

## The task format (metadata-below)

A task is a GitHub-style checkbox. Its metadata lives on an **indented line beneath** it (6
spaces), so the task reads as a plain sentence. An optional further-indented note can follow.

```markdown
- [ ] Email the landlord about the lease
      @2026-09-16 · manual
- [ ] Draft the proposal
      @2026-09-19 · chat · !high · #work · ★
      Lead with the pricing section.
- [x] Return library books
      @2026-09-12 · manual · ✓2026-09-13
```

Metadata tokens are `·`-separated, in this order:

| Token | Required | Meaning |
|---|---|---|
| `@<due>` | **yes** | Due date. Prefer ISO (`@2026-09-16`). `@today`, `@fri`, `@20aug` also parse. Every task needs a due date — if the user gives none, ask or pick a sensible one and say which. |
| `source` | yes | `calendar` · `chat` · `manual`. A task you add at the user's request in a chat is **`chat`**. `manual` is the implicit default and may be omitted. |
| `!priority` | no | `!high` / `!med` / `!low`. Only when the user asks — never assign priority on your own. |
| `#type` | no | A freeform category tag, e.g. `#work`, `#health`. |
| `★` | no | **Focus flag** — pulls the task into the panel's *Today* section regardless of its due date (the deadline is untouched). Add it when the user says they want to focus on / do something *today* even though it's due later; remove it to send the task back to its due-date bucket. |
| `✓<date>` | auto | Completion stamp. To mark a task done, set `- [x]` **and** add `✓<ISO date>` to the metadata line. |

## Rules

- **Never reformat or reorder lines you didn't add.** Preserve the user's own prose and spacing.
- **Every task needs `@due`.** No due date = it can't appear in the panel.
- Marking done = flip `- [ ]` to `- [x]` *and* append `✓<today's ISO date>`; don't delete the
  task (the morning routine prunes old done tasks itself).
- Keep edits minimal and surgical — Read the file, make the one change, save.
- After saving, tell the user in one line what changed and in which file.

## Typical requests

- "add a task to call the dentist friday" → append to `tasks.md`: `- [ ] Call the dentist` /
  `@<coming-friday ISO> · chat`.
- "I want to focus on the proposal today" (already a task due later) → add `★` to that task's
  metadata line in `tasks.md`.
- "mark the expense report done" → find it in `tasks.md`, flip to `[x]`, add `✓<today>`.
- "add a long-term goal: finish the driving test before 15 oct" → append to `longterm.md`:
  `- [ ] Finish the driving test` / `@2026-10-15 · chat`.
