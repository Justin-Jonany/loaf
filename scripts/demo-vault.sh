#!/bin/bash
# scripts/demo-vault.sh — build a throwaway vault for recording a Loaf demo.
#
# The vault starts empty (no brief, no tasks) so the first shot shows a fresh panel.
# A calendar file with a week of events, dated relative to today, stands in for Google
# Calendar: running the morning brief against it fills the panel without touching your
# real calendar. A couple of notes give the brief something to connect the events to.
#
# Usage: scripts/demo-vault.sh [DIR]    (default: ~/LoafDemo; safe to re-run)

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DIR="${1:-$HOME/LoafDemo}"
VAULT="$DIR/vault"
CALENDAR="$DIR/calendar.json"

# why: re-running wipes the directory, so refuse anything this script didn't create.
if [[ -e "$DIR" && ! -f "$DIR/.loaf-demo" ]]; then
  echo "demo-vault: $DIR exists and isn't a demo vault; pick another path" >&2
  exit 1
fi
rm -rf "$DIR"
mkdir -p "$VAULT/notes"
touch "$DIR/.loaf-demo"

d() { date -v"${1}d" +%F; }
# Calendar events carry an offset (tasks never do); macOS %z has no colon.
OFFSET="$(date +%z | sed -E 's/([0-9]{2})$/:\1/')"
at() { echo "$(d "$1")T$2:00$OFFSET"; }

printf '# Tasks\n' > "$VAULT/tasks.md"
printf '# Long-term\n' > "$VAULT/longterm.md"

cat > "$VAULT/notes/q4-roadmap.md" <<'EOF'
# Q4 roadmap

Outline is done. The hiring plan section is still empty, and Sarah flagged it last time.
EOF

cat > "$VAULT/notes/denver-trip.md" <<'EOF'
# Denver trip

Conference talk is on day two. Slides are drafted but need a final pass on the plane.
EOF

cat > "$VAULT/CLAUDE.md" <<'EOF'
# Vault notes

Personal preferences for Claude go here. Keep the brief short and friendly.
EOF

cat > "$CALENDAR" <<EOF
{
  "events": [
    {
      "id": "evt-standup",
      "summary": "Team standup",
      "start": "$(at +0 09:30)",
      "end": "$(at +0 09:45)",
      "description": "",
      "recurringEventId": "rec-standup"
    },
    {
      "id": "evt-roadmap-review",
      "summary": "Q4 roadmap review with Sarah",
      "start": "$(at +0 14:00)",
      "end": "$(at +0 15:00)",
      "description": "Walk through the draft. Bring the hiring plan."
    },
    {
      "id": "evt-dinner",
      "summary": "Dinner with Mike",
      "start": "$(at +1 19:00)",
      "end": "$(at +1 21:00)",
      "description": "Mike asked you to bring back the book you borrowed."
    },
    {
      "id": "evt-oil-change",
      "summary": "Car oil change",
      "start": "$(at +2 08:30)",
      "end": "$(at +2 09:30)",
      "description": "Drop off before work."
    },
    {
      "id": "evt-flight",
      "summary": "Flight to Denver",
      "start": "$(at +3 07:10)",
      "end": "$(at +3 09:05)",
      "description": "Check in online the day before."
    },
    {
      "id": "evt-talk",
      "summary": "Conference talk",
      "start": "$(at +4 11:00)",
      "end": "$(at +4 11:45)",
      "description": "Room B. Bring the clicker."
    },
    {
      "id": "evt-emily-1on1",
      "summary": "1:1 with Emily",
      "start": "$(at +6 10:00)",
      "end": "$(at +6 10:30)",
      "description": "She wants to talk about the team offsite."
    }
  ]
}
EOF

cat <<EOF
Demo vault ready at $VAULT

Open the panel on it (quit your normal Loaf first):
  LOAF_VAULT="$VAULT" "$REPO/dist/Loaf.app/Contents/MacOS/Loaf"

Build today's brief, using the demo calendar:
  "$REPO/routines/morning-brief/run.sh" --vault "$VAULT" --calendar-fixture "$CALENDAR" --force

Talk to Claude against the demo vault (loaf-notes reads LOAF_VAULT first):
  LOAF_VAULT="$VAULT" claude
EOF
