---
name: loaf-setup
description: Install and set up Loaf on this Mac — downloads the app, creates the notes vault, wires up the task format, schedules the morning brief, checks the Google Calendar connection, and builds a first brief. Use when the user says "set up loaf", "install loaf", or asks why their Loaf brief isn't running. Safe to re-run; it also repairs or updates an existing setup.
user-invocable: true
allowed-tools:
  - Read
  - Bash(bash *)
  - Bash(command -v *)
  - Bash(sw_vers *)
  - Bash(cat *)
  - Bash(ls *)
  - Bash(launchctl print *)
---

# Set up Loaf

Loaf is a macOS panel that shows a daily brief and task list from markdown files in a
folder (the **vault**). A scheduled `claude -p` run writes the brief each morning. This
skill gets a Mac from nothing to a working setup. Every step is idempotent, so re-running
it is also how to repair or update an install.

Go step by step, tell the user briefly what each step did, and stop to report clearly if
one fails rather than pressing on. The bundled scripts live in this plugin at
`${CLAUDE_PLUGIN_ROOT}/scripts/`.

## 1. Check prerequisites

- `sw_vers -productVersion` must be 14 or later. If not, stop: Loaf needs macOS 14+.
- `command -v claude` must resolve. The scheduled run happens outside this session under
  launchd's minimal environment, and `run.sh` only adds `~/.local/bin`, `/opt/homebrew/bin`
  and `/usr/local/bin` to `PATH`. If `claude` lives anywhere else, warn the user that the
  morning run won't find it, and suggest symlinking it into `~/.local/bin`.

## 2. Ask two things (skip what's already set)

If `~/.config/loaf/config.toml` exists, read it first and show the current values instead
of asking again, unless the user wants to change them.

1. **Where should the notes live?** Default `~/Notes`. Any folder works, including an
   existing one; Loaf only reads `brief.md`, `tasks.md` and `longterm.md` in it and never
   deletes anything.
2. **Should the brief build itself every morning?** Recommend yes. It schedules a launchd
   job that tries from 6am and catches up on wake if the Mac was asleep.

## 3. Install the routine, config, and schedule

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/install.sh" --skip-skills --vault "<vault>" [--schedule]
```

Pass `--schedule` only if the user said yes. `--skip-skills` is right here: this plugin
already provides the `loaf-notes` and `loaf-brief` skills. Report the paths it prints.

## 4. Install the app

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/install-app.sh"
```

This downloads the latest release, installs it (replacing an existing copy), and opens it.
The panel appears on the desktop with a loaf icon in the menu bar. On first launch it seeds
the vault with a `CLAUDE.md` for the user's personal preferences; mention they can fill it
in (tone, priorities, people) to make the brief more personal.

## 5. Check the calendar connection

The morning run reads today's events through the claude.ai **Google Calendar** connector,
using the tools `mcp__claude_ai_Google_Calendar__list_events` and
`mcp__claude_ai_Google_Calendar__search_events`.

- If a tool named `mcp__claude_ai_Google_Calendar__list_events` is available to you (it may
  be listed as a deferred tool you have to load first), call it for today to confirm it
  works, and tell the user how many events it found.
- If it isn't available, tell the user to connect Google Calendar at claude.ai → Settings →
  Connectors, then restart Claude Code and re-run this skill. Until then the brief can't read
  the calendar, and the morning run will report a failure instead of silently skipping it.

## 6. Build the first brief

Offer to build today's brief now rather than waiting for tomorrow morning. If the user
agrees:

```bash
bash "$HOME/Library/Application Support/Loaf/routines/morning-brief/run.sh" --force
```

It takes a minute or two. The panel repaints on its own when `brief.md` lands. If it fails,
show the last lines of the transcript path it printed.

## 7. Wrap up

Summarize in a few lines: where the vault is, whether the schedule is on, and the two
everyday skills: **loaf-notes** ("add a task to call the dentist friday") and
**loaf-brief** ("rebuild my brief").
