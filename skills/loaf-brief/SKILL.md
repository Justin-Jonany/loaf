---
name: loaf-brief
description: Rebuild the Loaf daily brief right now, on demand — for when the scheduled 6am morning run didn't fire, or you just want today's brief regenerated. Runs the morning-brief routine against the real vault and live calendar.
user-invocable: true
allowed-tools:
  - Read
  - Bash(cat *)
  - Bash(bash *)
---

# Rebuild the Loaf brief on demand

The Loaf morning brief normally runs unattended at ~6am. This skill triggers that same
routine now — use it when the scheduled run didn't fire or the user wants a fresh brief.

## How

1. Find the Loaf repo: read `~/.config/loaf/config.toml` (`Bash(cat ~/.config/loaf/config.toml)`)
   and take the `contract = "..."` path. The repo root is the directory that contains that
   `TASK-FORMAT.md`. If there is no `contract =` line, the skills aren't installed — tell the
   user to run `scripts/install.sh` from their clone, and stop.
2. Run the routine, forcing a rebuild even if today's brief already exists:
   `bash <repo>/routines/morning-brief/run.sh --force`
3. The routine writes `brief.md` (and may add calendar tasks to `tasks.md`) in the vault, then
   the panel repaints. Report to the user what the run printed — especially whether it
   succeeded, or wrote a failure signal.

## Notes

- This runs the real routine, which calls the live Google Calendar connector; it needs network.
- It does NOT take a date argument — it always builds *today's* brief. The `--force` flag only
  bypasses the "already built today" short-circuit so a rerun actually regenerates.
