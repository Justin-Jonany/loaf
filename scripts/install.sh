#!/usr/bin/env bash
set -euo pipefail

# Idempotent installer: wires this repo's clone into ~/.claude/skills and points
# ~/.config/loaf/config.toml at this repo's TASK-FORMAT.md so loaf-notes and
# loaf-brief can find the single-source task format. Safe to re-run any time
# (e.g. after moving the clone) — every step below replaces, not duplicates.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- Symlink skills so they stay in sync with the repo ---
mkdir -p "$HOME/.claude/skills"
ln -sfn "$REPO/skills/loaf-notes" "$HOME/.claude/skills/loaf-notes"
ln -sfn "$REPO/skills/loaf-brief" "$HOME/.claude/skills/loaf-brief"

# --- Write the contract pointer into config ---
CONFIG_DIR="$HOME/.config/loaf"
CONFIG="$CONFIG_DIR/config.toml"
mkdir -p "$CONFIG_DIR"
[ -f "$CONFIG" ] || cp "$REPO/config.example.toml" "$CONFIG"

CONTRACT_LINE="contract = \"$REPO/TASK-FORMAT.md\""
if grep -qE '^[[:space:]]*contract[[:space:]]*=' "$CONFIG"; then
  awk -v repl="$CONTRACT_LINE" '/^[[:space:]]*contract[[:space:]]*=/{print repl; next} {print}' "$CONFIG" > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"
else
  printf '\n%s\n' "$CONTRACT_LINE" >> "$CONFIG"
fi

echo "Installed Loaf skills:"
echo "  ~/.claude/skills/loaf-notes -> $REPO/skills/loaf-notes"
echo "  ~/.claude/skills/loaf-brief -> $REPO/skills/loaf-brief"
echo "Wrote contract pointer to $CONFIG:"
echo "  $CONTRACT_LINE"
echo
echo "This installer does NOT touch your vault (tasks.md/brief.md) and does NOT"
echo "schedule the morning routine. To schedule the 6am morning-brief run via launchd:"
echo
echo "  sed \"s|REPLACE_WITH_ABSOLUTE_REPO_PATH|$REPO|g\" \\"
echo "    \"$REPO/routines/morning-brief/com.loaf.morning-brief.plist\" \\"
echo "    > ~/Library/LaunchAgents/com.loaf.morning-brief.plist"
echo "  launchctl bootstrap gui/\$(id -u) ~/Library/LaunchAgents/com.loaf.morning-brief.plist"
echo
echo "(If you're re-running this after moving the clone, first bootout the old job:"
echo "  launchctl bootout gui/\$(id -u)/com.loaf.morning-brief"
echo "then bootstrap again with the command above.)"
