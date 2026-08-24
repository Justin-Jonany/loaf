#!/bin/bash
# routines/morning-brief/dry_run.sh — the C1 test harness (ROADMAP.md -> C1 Tests).
#
# Runs the real SKILL.md prompt through a real `claude -p` invocation (via run.sh)
# against a fixture vault + fixture calendar checked into
# routines/morning-brief/fixtures/, instead of the live Google Calendar. Four scenarios:
#
#   decision-day           overlapping calendar events -> expects a decision signal
#   clear-day               an uneventful day -> expects NO interruption
#   failure-bad-calendar    an unparseable calendar fixture -> expects the routine to
#                            self-report failure and leave brief.md untouched
#   failure-forced           FOOLSCAP_FORCE_FAILURE=1, no Claude call at all -> exercises
#                            run.sh's own shell-level backstop (a throwaway vault, not a
#                            checked-in fixture)
#
# For decision-day/clear-day/failure-bad-calendar the fixture vault IS the git-tracked
# directory under fixtures/ — the run mutates it in place so `git diff` shows a real
# before/after, exactly what ROADMAP.md's Verify line asks for. This script prints that
# diff and then reverts the fixture (`git checkout --`) so the tracked "before" state is
# available for the next run; capture the printed diff before it scrolls away, or re-run
# with the CAPTURE_DIR var below to also save copies to disk.
#
# Usage: ./dry_run.sh <decision-day|clear-day|failure-bad-calendar|failure-forced|all>

set -uo pipefail

ROUTINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$ROUTINE_DIR/../.." && pwd)"
FIXTURES="$ROUTINE_DIR/fixtures"

hr() { printf '%.0s=' {1..78}; echo; }

check_tasks() {
  local vault="$1"
  hr
  echo "### foolscap-routine-check (feeds tasks.md through TaskBlock — A1's parser)"
  ( cd "$REPO_ROOT" && swift run --quiet foolscap-routine-check "$vault/tasks.md" )
  local status=$?
  if [[ -f "$vault/longterm.md" ]]; then
    ( cd "$REPO_ROOT" && swift run --quiet foolscap-routine-check "$vault/longterm.md" )
  fi
  return $status
}

show_diff_and_revert() {
  local vault="$1"
  hr
  echo "### git diff (before -> after) — brief.md / tasks.md / longterm.md"
  ( cd "$REPO_ROOT" && git --no-pager diff -- "$vault/brief.md" "$vault/tasks.md" "$vault/longterm.md" )
  hr
  echo "### untracked files left by this run (e.g. the decision/failure signal)"
  ( cd "$REPO_ROOT" && git status --porcelain -- "$vault" | grep '^??' || echo "(none)" )
  if [[ -f "$vault/.routine-signal.md" ]]; then
    echo "--- $vault/.routine-signal.md ---"
    cat "$vault/.routine-signal.md"
  fi
  hr
  echo "### reverting the fixture to its tracked 'before' state for the next run"
  ( cd "$REPO_ROOT" && git checkout -- "$vault/brief.md" "$vault/tasks.md" "$vault/longterm.md" 2>/dev/null )
  ( cd "$REPO_ROOT" && git clean -fq -- "$vault/.routine-signal.md" 2>/dev/null )
}

scenario_decision_day() {
  local vault="$FIXTURES/decision-day/vault"
  hr; echo "SCENARIO: decision-day (expect: a decision signal, no interruption suppressed)"; hr
  "$ROUTINE_DIR/run.sh" --vault "$vault" --calendar-fixture "$FIXTURES/decision-day/calendar.json"
  local exit_code=$?
  echo "run.sh exit: $exit_code"
  check_tasks "$vault"; local check_exit=$?
  if [[ -f "$vault/.routine-signal.md" ]]; then
    echo "PASS: decision signal present, as expected for an overlapping-events day"
  else
    echo "FAIL: expected .routine-signal.md (status: needs-decision), found none"
  fi
  show_diff_and_revert "$vault"
  return 0
}

scenario_clear_day() {
  local vault="$FIXTURES/clear-day/vault"
  hr; echo "SCENARIO: clear-day (expect: NO interruption)"; hr
  "$ROUTINE_DIR/run.sh" --vault "$vault" --calendar-fixture "$FIXTURES/clear-day/calendar.json"
  local exit_code=$?
  echo "run.sh exit: $exit_code"
  check_tasks "$vault"; local check_exit=$?
  if [[ -f "$vault/.routine-signal.md" ]]; then
    echo "FAIL: expected no decision/failure signal on a clear day, found $vault/.routine-signal.md"
  else
    echo "PASS: no signal file — a clear day stayed silent"
  fi
  show_diff_and_revert "$vault"
  return 0
}

scenario_failure_bad_calendar() {
  local vault="$FIXTURES/failure-bad-calendar/vault"
  hr; echo "SCENARIO: failure-bad-calendar (expect: failure signal, brief.md untouched)"; hr
  local brief_before
  brief_before="$(cat "$vault/brief.md")"
  "$ROUTINE_DIR/run.sh" --vault "$vault" --calendar-fixture "$FIXTURES/failure-bad-calendar/calendar.broken.json"
  local exit_code=$?
  echo "run.sh exit: $exit_code"
  if [[ "$(cat "$vault/brief.md")" == "$brief_before" ]]; then
    echo "PASS: brief.md is byte-for-byte unchanged — no stale-looking-fresh brief"
  else
    echo "FAIL: brief.md changed despite a forced calendar failure"
  fi
  if [[ -f "$vault/.routine-signal.md" ]] && grep -q '^status: failed$' "$vault/.routine-signal.md"; then
    echo "PASS: failure signal present with status: failed"
  else
    echo "FAIL: expected $vault/.routine-signal.md with status: failed"
  fi
  show_diff_and_revert "$vault"
  return 0
}

scenario_failure_forced() {
  hr; echo "SCENARIO: failure-forced (FOOLSCAP_FORCE_FAILURE=1, no Claude call)"; hr
  local tmp
  tmp="$(mktemp -d)"
  printf '<!-- built: 2026-08-22T06:00:00-07:00 -->\n# Brief\nYesterday'"'"'s brief, untouched by this scenario.\n' > "$tmp/brief.md"
  FOOLSCAP_FORCE_FAILURE=1 "$ROUTINE_DIR/run.sh" --vault "$tmp"
  local exit_code=$?
  echo "run.sh exit: $exit_code"
  cat "$tmp/brief.md"
  echo "--- $tmp/.routine-signal.md ---"
  cat "$tmp/.routine-signal.md" 2>/dev/null || echo "MISSING"
  rm -rf "$tmp"
  return 0
}

case "${1:-}" in
  decision-day) scenario_decision_day ;;
  clear-day) scenario_clear_day ;;
  failure-bad-calendar) scenario_failure_bad_calendar ;;
  failure-forced) scenario_failure_forced ;;
  all)
    scenario_decision_day
    scenario_clear_day
    scenario_failure_bad_calendar
    scenario_failure_forced
    ;;
  *)
    echo "usage: $0 <decision-day|clear-day|failure-bad-calendar|failure-forced|all>" >&2
    exit 2
    ;;
esac
