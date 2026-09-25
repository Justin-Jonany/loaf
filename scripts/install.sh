#!/usr/bin/env bash
set -euo pipefail

# Idempotent installer for everything Loaf needs outside the app itself. Run it from a
# clone, or let the `loaf-setup` skill run it from the installed Claude Code plugin.
# Safe to re-run any time — every step replaces, never duplicates.
#
#   scripts/install.sh [--vault PATH] [--schedule] [--skip-skills]
#
#   --vault PATH    write `vault = "PATH"` to the config (default: leave it as is)
#   --schedule      install (or refresh) the launchd job that runs the morning brief
#   --skip-skills   don't copy loaf-notes/loaf-brief into ~/.claude/skills; the plugin
#                   install already provides them
#
# The routine's runtime files (TASK-FORMAT.md + routines/morning-brief/) are copied to a
# fixed support directory and everything long-lived points there, not at this source
# tree: a plugin's install directory moves on every update, and a clone can be moved.
# Re-run this after pulling or updating to refresh the copy.
#
# LOAF_DRY_LAUNCHCTL=1 prints the launchctl commands instead of running them (tests).

SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUPPORT="$HOME/Library/Application Support/Loaf"
CONFIG_DIR="$HOME/.config/loaf"
CONFIG="$CONFIG_DIR/config.toml"
LABEL="com.loaf.morning-brief"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

VAULT=""
SCHEDULE=""
SKIP_SKILLS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --vault) VAULT="$2"; shift 2 ;;
    --schedule) SCHEDULE=1; shift ;;
    --skip-skills) SKIP_SKILLS=1; shift ;;
    *) echo "install.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done

# Replaces a top-level `key = ...` line in the config, or appends one. Only matches
# before the first [section] header, since these keys are top-level.
set_config_key() {
  local key="$1" line="$2"
  if awk -v k="$key" '/^\[/{exit 1} $0 ~ "^[[:space:]]*"k"[[:space:]]*=" {found=1; exit} END{exit !found}' "$CONFIG"; then
    awk -v k="$key" -v repl="$line" '
      /^\[/ {insection=1}
      !insection && $0 ~ "^[[:space:]]*"k"[[:space:]]*=" {print repl; next}
      {print}' "$CONFIG" > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"
  else
    # Prepend so the key stays top-level even if the file ends in a [section].
    { printf '%s\n' "$line"; cat "$CONFIG"; } > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"
  fi
}

# --- Runtime copy the routine and the skills read from --------------------------------
rm -rf "$SUPPORT/routines"
mkdir -p "$SUPPORT/routines/morning-brief"
cp "$SOURCE/TASK-FORMAT.md" "$SUPPORT/TASK-FORMAT.md"
# The fixtures are test data for dry_run.sh, which only makes sense in a clone.
for f in run.sh SKILL.md; do
  cp "$SOURCE/routines/morning-brief/$f" "$SUPPORT/routines/morning-brief/$f"
done

# --- Skills: independent copies; editing an installed one never touches the source ---
if [[ -z "$SKIP_SKILLS" ]]; then
  mkdir -p "$HOME/.claude/skills"
  for skill in loaf-notes loaf-brief; do
    rm -rf "$HOME/.claude/skills/$skill"
    cp -R "$SOURCE/skills/$skill" "$HOME/.claude/skills/$skill"
  done
fi

# --- Config ------------------------------------------------------------------------
mkdir -p "$CONFIG_DIR"
[ -f "$CONFIG" ] || cp "$SOURCE/config.example.toml" "$CONFIG"
set_config_key contract "contract = \"$SUPPORT/TASK-FORMAT.md\""
[[ -n "$VAULT" ]] && set_config_key vault "vault = \"$VAULT\""

# --- Schedule ----------------------------------------------------------------------
launchctl_run() {
  if [[ -n "${LOAF_DRY_LAUNCHCTL:-}" ]]; then echo "(dry) launchctl $*"; else launchctl "$@"; fi
}
if [[ -n "$SCHEDULE" ]]; then
  mkdir -p "$(dirname "$PLIST")"
  sed "s|REPLACE_WITH_ABSOLUTE_REPO_PATH|$SUPPORT|g" \
    "$SOURCE/routines/morning-brief/$LABEL.plist" > "$PLIST"
  # bootout fails when the job isn't loaded yet; that's the expected first-install case.
  launchctl_run bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  launchctl_run bootstrap "gui/$(id -u)" "$PLIST"
fi

echo "Loaf installed:"
echo "  runtime copy  $SUPPORT"
echo "  config        $CONFIG"
[[ -z "$SKIP_SKILLS" ]] && echo "  skills        ~/.claude/skills/loaf-notes, ~/.claude/skills/loaf-brief"
[[ -n "$VAULT" ]] && echo "  vault         $VAULT"
if [[ -n "$SCHEDULE" ]]; then
  echo "  schedule      $PLIST (mornings from 6:00)"
else
  echo
  echo "The morning brief is not scheduled. Re-run with --schedule to add the launchd job."
fi
