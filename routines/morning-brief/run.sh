#!/bin/bash
# routines/morning-brief/run.sh — invokes the morning brief routine (SKILL.md) as a
# non-interactive `claude -p` run against a real vault.
#
# Scheduling (ROADMAP.md -> C1): run this from launchd at ~6am local time via
# com.foolscap.morning-brief.plist in this directory (`launchctl bootstrap` it once —
# see the comment at the top of that file for the exact command). launchd's
# StartCalendarInterval jobs are NOT dropped when the Mac is asleep at the scheduled
# time — launchd runs a missed one as soon as the system is next awake, which is the
# "catch up on wake" behaviour DESIGN.md asks for, with no extra code here. If you want
# the routine to run even when the lid is closed / the Mac is fully asleep (not just
# idle), pair this with `sudo pmset repeat wake MTWRFSU 06:00:00` — optional, not
# configured by this script.
#
# Usage:
#   ./run.sh                                    # production: real vault, live calendar
#   ./run.sh --vault DIR                         # override the vault path
#   ./run.sh --calendar-fixture FILE             # dry run: read FILE instead of the
#                                                 # live Google Calendar MCP tools
#   FOOLSCAP_FORCE_FAILURE=1 ./run.sh            # skip Claude entirely, exercise only
#                                                 # the shell-level failure-signal path
#                                                 # (see routines/morning-brief/dry_run.sh)
#
# Vault resolution mirrors Sources/FoolscapCore/Vault.swift's `resolveRoot`:
# $FOOLSCAP_VAULT -> config.toml's `vault =` -> ~/Notes. --vault overrides all of that.

set -uo pipefail

ROUTINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${FOOLSCAP_CONFIG:-$HOME/.config/foolscap/config.toml}"

VAULT=""
CALENDAR_FIXTURE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --vault) VAULT="$2"; shift 2 ;;
    --calendar-fixture) CALENDAR_FIXTURE="$2"; shift 2 ;;
    *) echo "run.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done

expand_tilde() {
  case "$1" in
    "~") echo "$HOME" ;;
    "~/"*) echo "$HOME/${1#"~/"}" ;;
    *) echo "$1" ;;
  esac
}

if [[ -z "$VAULT" ]]; then
  if [[ -n "${FOOLSCAP_VAULT:-}" ]]; then
    VAULT="$(expand_tilde "$FOOLSCAP_VAULT")"
  elif [[ -f "$CONFIG_PATH" ]]; then
    CONFIGURED="$(grep -E '^[[:space:]]*vault[[:space:]]*=' "$CONFIG_PATH" | head -1 | sed -E 's/^[[:space:]]*vault[[:space:]]*=[[:space:]]*"?([^"]*)"?[[:space:]]*$/\1/')"
    if [[ -n "$CONFIGURED" ]]; then VAULT="$(expand_tilde "$CONFIGURED")"; fi
  fi
fi
VAULT="${VAULT:-$HOME/Notes}"

# why: overridable so dry_run.sh fixtures can pin a deterministic "today" for the 7-day
# lookahead window; production leaves this unset and gets the real date.
TODAY="${FOOLSCAP_TODAY:-$(date +%F)}"
# ISO 8601 with a colon in the UTC offset (macOS `date %z` omits it) — see SKILL.md ->
# "Writing brief.md" for the exact format D1 (ROADMAP.md) is expected to parse.
BUILD_TIME="$(date +%FT%T%z | sed -E 's/([+-][0-9]{2})([0-9]{2})$/\1:\2/')"

SIGNAL_FILE="$VAULT/.routine-signal.md"
BRIEF_FILE="$VAULT/brief.md"

write_failure_signal() {
  local reason="$1"
  mkdir -p "$VAULT"
  cat > "$SIGNAL_FILE" <<EOF
status: failed
at: $BUILD_TIME
reason: $reason
EOF
}

# --- Forced-failure test path -------------------------------------------------------
# Deterministic stand-in for "Claude couldn't run at all" (network down, auth expired,
# no budget) — see ROADMAP.md -> C1 Tests: "a forced failure leaves the failure signal,
# not a stale brief." No Claude invocation happens; this exercises exactly the same
# signal-writing code the real crash-recovery path below uses.
if [[ "${FOOLSCAP_FORCE_FAILURE:-}" == "1" ]]; then
  echo "run.sh: FOOLSCAP_FORCE_FAILURE=1 — skipping the Claude invocation entirely"
  write_failure_signal "forced failure (FOOLSCAP_FORCE_FAILURE=1) — simulates the routine being unable to run at all"
  echo "run.sh: wrote failure signal to $SIGNAL_FILE"
  exit 1
fi

mkdir -p "$VAULT"

# --- Build the prompt ----------------------------------------------------------------
# Strip SKILL.md's leading `---`-fenced YAML frontmatter; everything after the second
# `---` fence is the actual instructions.
SKILL_BODY="$(awk '/^---$/{n++; next} n>=2{print}' "$ROUTINE_DIR/SKILL.md")"

if [[ -n "$CALENDAR_FIXTURE" ]]; then
  CALENDAR_LINE="Calendar source: DRY RUN — read the fixture at $CALENDAR_FIXTURE with the Read tool. Do not call any Google Calendar tool even if offered; none should be available, but this fixture is authoritative if one is."
  ALLOWED_TOOLS=(Read Write Edit)
  DISALLOWED_TOOLS=(
    "mcp__claude_ai_Google_Calendar__list_events"
    "mcp__claude_ai_Google_Calendar__search_events"
    "mcp__claude_ai_Google_Calendar__get_event"
    "mcp__claude_ai_Google_Calendar__list_calendars"
    "mcp__claude_ai_Google_Calendar__create_event"
    "mcp__claude_ai_Google_Calendar__update_event"
    "mcp__claude_ai_Google_Calendar__delete_event"
    "mcp__claude_ai_Google_Calendar__respond_to_event"
    "mcp__claude_ai_Google_Calendar__suggest_time"
    "Bash" "WebFetch" "WebSearch"
  )
  ADD_DIRS=("$VAULT" "$(dirname "$CALENDAR_FIXTURE")")
else
  CALENDAR_LINE="Calendar source: LIVE — call the Google Calendar MCP tools (list_events / search_events) for $TODAY."
  # These tool names match the Google Calendar MCP server as configured in this repo's
  # dev environment (see the deferred-tools list any Claude Code session in this repo
  # gets). If your own machine's MCP config names that server differently, update the
  # two read-only tool names below to match — everything else in this script is
  # environment-independent.
  ALLOWED_TOOLS=(Read Write Edit "mcp__claude_ai_Google_Calendar__list_events" "mcp__claude_ai_Google_Calendar__search_events")
  DISALLOWED_TOOLS=(
    "mcp__claude_ai_Google_Calendar__create_event"
    "mcp__claude_ai_Google_Calendar__update_event"
    "mcp__claude_ai_Google_Calendar__delete_event"
    "mcp__claude_ai_Google_Calendar__respond_to_event"
    "Bash" "WebFetch" "WebSearch"
  )
  ADD_DIRS=("$VAULT")
fi

PREAMBLE="Facts for this run (authoritative — do not infer or override any of these):
- Today's date (local): $TODAY
- Build timestamp to stamp brief.md with (local, with offset): $BUILD_TIME
- Vault directory (absolute path, read/write everything below relative to this): $VAULT
- $CALENDAR_LINE

---

$SKILL_BODY"

# --- Snapshot brief.md so a bad run can't leave a fresh-looking-but-broken file ------
BRIEF_BACKUP=""
if [[ -f "$BRIEF_FILE" ]]; then
  BRIEF_BACKUP="$(mktemp)"
  cp "$BRIEF_FILE" "$BRIEF_BACKUP"
fi

LOG_DIR="${FOOLSCAP_ROUTINE_LOG_DIR:-$HOME/Library/Logs/Foolscap/morning-brief}"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%dT%H%M%S).log"

ADD_DIR_ARGS=()
for d in "${ADD_DIRS[@]}"; do ADD_DIR_ARGS+=(--add-dir "$d"); done

echo "run.sh: vault=$VAULT today=$TODAY mode=$([[ -n "$CALENDAR_FIXTURE" ]] && echo dry-run || echo live)"
echo "run.sh: transcript -> $LOG_FILE"

set -o pipefail
claude -p "$PREAMBLE" \
  "${ADD_DIR_ARGS[@]}" \
  --allowedTools "${ALLOWED_TOOLS[@]}" \
  --disallowedTools "${DISALLOWED_TOOLS[@]}" \
  --permission-mode bypassPermissions \
  --output-format text \
  2>&1 | tee "$LOG_FILE"
CLAUDE_EXIT=${PIPESTATUS[0]}
set +o pipefail

echo "run.sh: claude exited $CLAUDE_EXIT"

# --- Shell-level backstop -------------------------------------------------------------
# Belt-and-suspenders for SKILL.md's own "If something goes wrong" section. Two cases:
#   (a) the process itself errored (crashed, no budget, unreachable) — SKILL.md never
#       got a chance to self-report, so this script must write the failure signal;
#   (b) the process exited clean and correctly self-reported failure (status: failed) —
#       trust that, but still restore brief.md as a cheap safety net in case it got
#       written before the failure was noticed.
SIGNAL_NOW_FAILED=0
if [[ -f "$SIGNAL_FILE" ]] && grep -q "^status: failed$" "$SIGNAL_FILE"; then
  SIGNAL_NOW_FAILED=1
fi

if [[ $CLAUDE_EXIT -ne 0 ]] || [[ $SIGNAL_NOW_FAILED -eq 1 ]]; then
  if [[ -n "$BRIEF_BACKUP" ]]; then
    cp "$BRIEF_BACKUP" "$BRIEF_FILE"
    echo "run.sh: restored brief.md from before this run"
  fi
  if [[ $SIGNAL_NOW_FAILED -eq 0 ]]; then
    write_failure_signal "claude exited $CLAUDE_EXIT without completing the run — see $LOG_FILE"
    echo "run.sh: wrote failure signal to $SIGNAL_FILE (shell-level backstop)"
  fi
  [[ -n "$BRIEF_BACKUP" ]] && rm -f "$BRIEF_BACKUP"
  exit 1
fi

[[ -n "$BRIEF_BACKUP" ]] && rm -f "$BRIEF_BACKUP"
exit 0
