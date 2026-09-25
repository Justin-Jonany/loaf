---
name: loaf-notes
description: Add or edit tasks and long-term goals in the user's Loaf vault ($LOAF_VAULT, the config's vault, or ~/Notes) from any directory. Use when the user asks to add/change/complete a task, jot a to-do, add a long-term goal, or "put X in my loaf notes / my notes / my brief". Knows the vault location and the metadata-below task format so edits parse correctly.
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

Resolve the vault root in this order (first that exists wins). Run the checks every time
before touching a file — don't assume a path from an earlier session or from memory:

1. `$LOAF_VAULT` if set — `printenv LOAF_VAULT`.
2. The `vault = "..."` line in `~/.config/loaf/config.toml` (tilde is expanded).
3. Default: `~/Notes`.

Operate on files *inside the resolved vault* — never guess a path elsewhere.

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

## The task format

The task format is defined once in the Loaf repo's `TASK-FORMAT.md` — this skill does not
restate it, so it can never drift. Before editing tasks:

1. Read the contract pointer: look for a line `contract = "..."` in `~/.config/loaf/config.toml`
   (`Bash(cat ~/.config/loaf/config.toml)`), and `Read` the file it points to. That file is
   authoritative for the metadata-below format and every token.
2. If there is no `contract =` line (or the file is missing), the Loaf skills aren't wired up
   on this machine — tell the user to run the `loaf-setup` skill (or `scripts/install.sh` from
   a clone), and stop rather than guessing a format.
3. Also `Read` `<vault>/CLAUDE.md` (the vault you resolved above) — it holds the user's own
   personal preferences (tone, people, how they like tasks phrased). Respect it; it is NOT the
   format spec.

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
- "mark the expense report done" → find it in `tasks.md`, flip to `[x]`, add `✓<today>`.
- "add a long-term goal: finish the driving test before 15 oct" → append to `longterm.md`:
  `- [ ] Finish the driving test` / `@2026-10-15 · chat`.
