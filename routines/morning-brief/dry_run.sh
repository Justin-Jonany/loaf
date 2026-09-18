#!/bin/bash
# routines/morning-brief/dry_run.sh — the C1 test harness (ROADMAP.md -> C1 Tests).
#
# Runs the real SKILL.md prompt through a real `claude -p` invocation (via run.sh)
# against a fixture vault + fixture calendar checked into
# routines/morning-brief/fixtures/, instead of the live Google Calendar. Five scenarios:
#
#   decision-day           overlapping calendar events -> expects a decision signal
#   clear-day               an uneventful day -> expects NO interruption
#   lookahead                a 7-day-out event, a same-day-window event, one beyond the
#                            window, and one whose task the user already finished early
#                            and archived -> expects the window bound + cross-run de-dup
#                            (DECISIONS.md 2026-09-12) + de-dup against archive/, bounded
#                            by due date so a same-titled older entry suppresses nothing
#   recurrence-tiering       a recurring class + a recurring focus block alongside a
#                            one-off coffee chat and a one-off graded deliverable ->
#                            expects the recurring pair to stay context (never tasks) and
#                            the one-offs to become calendar tasks (DECISIONS.md 2026-09-13)
#   interview-day            a recurring class alongside a one-off interview and a bare
#                            one-off appointment with no description/attendees -> expects
#                            both one-offs to become calendar tasks (proving recurrence,
#                            not "has an action item," decides the tier) and the class to
#                            stay context
#   failure-bad-calendar    an unparseable calendar fixture -> expects the routine to
#                            self-report failure and leave brief.md untouched
#   failure-forced           LOAF_FORCE_FAILURE=1, no Claude call at all -> exercises
#                            run.sh's own shell-level backstop (a throwaway vault, not a
#                            checked-in fixture)
#
# decision-day and clear-day pin LOAF_TODAY=2026-08-23 (matching their fixture
# events' date) so the 7-day window lands on them the same way it always did before the
# window existed; lookahead, recurrence-tiering, and interview-day pin
# LOAF_TODAY=2026-09-14 to exercise the window / tiering on that date.
#
# For decision-day/clear-day/lookahead/failure-bad-calendar the fixture vault IS the
# git-tracked directory under fixtures/ — the run mutates it in place so `git diff` shows
# a real before/after, exactly what ROADMAP.md's Verify line asks for. This script prints
# that diff and then reverts the fixture (`git checkout --`) so the tracked "before" state
# is available for the next run; capture the printed diff before it scrolls away, or
# re-run with the CAPTURE_DIR var below to also save copies to disk.
#
# Usage: ./dry_run.sh <decision-day|clear-day|lookahead|recurrence-tiering|interview-day|failure-bad-calendar|failure-forced|all>

set -uo pipefail

ROUTINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$ROUTINE_DIR/../.." && pwd)"
FIXTURES="$ROUTINE_DIR/fixtures"

hr() { printf '%.0s=' {1..78}; echo; }

check_tasks() {
  local vault="$1"
  hr
  echo "### loaf-routine-check (feeds tasks.md through TaskBlock — A1's parser)"
  ( cd "$REPO_ROOT" && swift run --quiet loaf-routine-check "$vault/tasks.md" )
  local status=$?
  if [[ -f "$vault/longterm.md" ]]; then
    ( cd "$REPO_ROOT" && swift run --quiet loaf-routine-check "$vault/longterm.md" )
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
  LOAF_TODAY=2026-08-23 "$ROUTINE_DIR/run.sh" --vault "$vault" --calendar-fixture "$FIXTURES/decision-day/calendar.json"
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
  LOAF_TODAY=2026-08-23 "$ROUTINE_DIR/run.sh" --vault "$vault" --calendar-fixture "$FIXTURES/clear-day/calendar.json"
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

scenario_lookahead() {
  local vault="$FIXTURES/lookahead/vault"
  hr; echo "SCENARIO: lookahead (expect: 7-day window + cross-run de-dup)"; hr
  LOAF_TODAY=2026-09-14 "$ROUTINE_DIR/run.sh" --vault "$vault" --calendar-fixture "$FIXTURES/lookahead/calendar.json"
  local exit_code=$?
  echo "run.sh exit: $exit_code"
  check_tasks "$vault"; local check_exit=$?

  local vendor_count board_count
  if grep -q '@2026-09-16' "$vault/tasks.md" && grep -A1 '@2026-09-16' "$vault/tasks.md" | grep -q 'calendar'; then
    echo "PASS: a calendar task for the Design review (@2026-09-16) was added — the 7-day window reached a future event"
  else
    echo "FAIL: expected a new calendar task dated @2026-09-16 (Design review), found none"
  fi

  vendor_count="$(grep -c '@2026-09-17' "$vault/tasks.md" | tr -d ' ')"
  if [[ "$vendor_count" -eq 1 ]]; then
    echo "PASS: exactly one task references @2026-09-17 — the pre-seeded vendor-call task was not duplicated"
  else
    echo "FAIL: expected exactly 1 task line with @2026-09-17, found $vendor_count"
  fi

  local archived_count
  archived_count="$(grep -c '@2026-09-19' "$vault/tasks.md" | tr -d ' ')"
  if [[ "$archived_count" -eq 0 ]]; then
    echo "PASS: no task references @2026-09-19 — the compliance training was left alone, its task having already been archived (archive/2026-09.md)"
  else
    echo "FAIL: expected 0 task lines with @2026-09-19, found $archived_count — an archived task was resurrected from the calendar"
  fi

  if grep -q '@2026-09-16' "$vault/tasks.md"; then
    echo "PASS: the Design review (@2026-09-16) survived the archive scan — a same-titled entry archived under a different date (archive/2026-08.md) did not suppress it"
  else
    echo "FAIL: the Design review (@2026-09-16) was suppressed by the August archive entry — the archive match is not bounded by due date"
  fi

  board_count="$(grep -c '@2026-09-24' "$vault/tasks.md" | tr -d ' ')"
  if [[ "$board_count" -eq 0 ]]; then
    echo "PASS: no task references @2026-09-24 — the board meeting (10 days out) stayed outside the window"
  else
    echo "FAIL: expected no task with @2026-09-24, found $board_count"
  fi

  if [[ -f "$vault/.routine-signal.md" ]]; then
    echo "NOTE: .routine-signal.md was written on this run — not asserted pass/fail, but a clean lookahead day is expected to be silent:"
    cat "$vault/.routine-signal.md"
  else
    echo "NOTE: no .routine-signal.md written — consistent with a clean lookahead day staying silent"
  fi

  show_diff_and_revert "$vault"
  return 0
}

scenario_recurrence_tiering() {
  local vault="$FIXTURES/recurrence-tiering/vault"
  hr; echo "SCENARIO: recurrence-tiering (expect: recurring class + focus block stay context; one-offs become tasks)"; hr
  LOAF_TODAY=2026-09-14 "$ROUTINE_DIR/run.sh" --vault "$vault" --calendar-fixture "$FIXTURES/recurrence-tiering/calendar.json"
  local exit_code=$?
  echo "run.sh exit: $exit_code"
  check_tasks "$vault"; local check_exit=$?

  local calendar_count
  calendar_count="$(grep -cE '·[[:space:]]*calendar' "$vault/tasks.md" | tr -d ' ')"
  if [[ "$calendar_count" -eq 2 ]]; then
    echo "PASS: exactly 2 calendar-source tasks — the coffee chat and the case study, not the recurring pair"
  else
    echo "FAIL: expected exactly 2 calendar-source task lines, found $calendar_count"
  fi

  if grep -qi 'CS 486' "$vault/tasks.md" || grep -qi 'Focus Session' "$vault/tasks.md"; then
    echo "FAIL: a recurring block (CS 486 or Focus Session) was added as a task — recurrence should keep it context-only"
  else
    echo "PASS: no task references the recurring CS 486 lecture or Focus Session"
  fi

  if grep -q '@2026-09-14' "$vault/tasks.md"; then
    echo "PASS: a calendar task dated @2026-09-14 exists"
  else
    echo "FAIL: expected a calendar task dated @2026-09-14, found none"
  fi

  if [[ -f "$vault/.routine-signal.md" ]]; then
    echo "NOTE: .routine-signal.md was written on this run"
    cat "$vault/.routine-signal.md"
  else
    echo "NOTE: no .routine-signal.md written"
  fi

  show_diff_and_revert "$vault"
  return 0
}

scenario_interview_day() {
  local vault="$FIXTURES/interview-day/vault"
  hr; echo "SCENARIO: interview-day (expect: a bare one-off with no description/attendees still becomes a task)"; hr
  LOAF_TODAY=2026-09-14 "$ROUTINE_DIR/run.sh" --vault "$vault" --calendar-fixture "$FIXTURES/interview-day/calendar.json"
  local exit_code=$?
  echo "run.sh exit: $exit_code"
  check_tasks "$vault"; local check_exit=$?

  local calendar_count
  calendar_count="$(grep -cE '·[[:space:]]*calendar' "$vault/tasks.md" | tr -d ' ')"
  if [[ "$calendar_count" -eq 2 ]]; then
    echo "PASS: exactly 2 calendar-source tasks — the interview and the dentist appointment"
  else
    echo "FAIL: expected exactly 2 calendar-source task lines, found $calendar_count"
  fi

  if grep -qi 'ENGL 378' "$vault/tasks.md"; then
    echo "FAIL: the recurring ENGL 378 lecture was added as a task — recurrence should keep it context-only"
  else
    echo "PASS: no task references the recurring ENGL 378 lecture"
  fi

  if grep -iq 'dentist' "$vault/tasks.md"; then
    echo "PASS: a task exists for the bare Dentist appointment — a one-off with no description/attendees still became a task"
  else
    echo "FAIL: expected a task for the Dentist appointment, found none"
  fi

  if [[ -f "$vault/.routine-signal.md" ]]; then
    echo "NOTE: .routine-signal.md was written on this run"
    cat "$vault/.routine-signal.md"
  else
    echo "NOTE: no .routine-signal.md written"
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
  hr; echo "SCENARIO: failure-forced (LOAF_FORCE_FAILURE=1, no Claude call)"; hr
  local tmp
  tmp="$(mktemp -d)"
  printf '<!-- built: 2026-08-22T06:00:00-07:00 -->\n# Brief\nYesterday'"'"'s brief, untouched by this scenario.\n' > "$tmp/brief.md"
  LOAF_FORCE_FAILURE=1 "$ROUTINE_DIR/run.sh" --vault "$tmp"
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
  lookahead) scenario_lookahead ;;
  recurrence-tiering) scenario_recurrence_tiering ;;
  interview-day) scenario_interview_day ;;
  failure-bad-calendar) scenario_failure_bad_calendar ;;
  failure-forced) scenario_failure_forced ;;
  all)
    scenario_decision_day
    scenario_clear_day
    scenario_lookahead
    scenario_recurrence_tiering
    scenario_interview_day
    scenario_failure_bad_calendar
    scenario_failure_forced
    ;;
  *)
    echo "usage: $0 <decision-day|clear-day|lookahead|recurrence-tiering|interview-day|failure-bad-calendar|failure-forced|all>" >&2
    exit 2
    ;;
esac
