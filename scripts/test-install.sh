#!/usr/bin/env bash
set -euo pipefail

# Exercises scripts/install.sh and scripts/install-app.sh against a throwaway HOME, so
# it never touches the real config, skills, launchd jobs, or installed app. Needs
# dist/Loaf.app (run ./build.sh first). Exits non-zero on the first failed check.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export LOAF_DRY_LAUNCHCTL=1
SUPPORT="$T/Library/Application Support/Loaf"
CONFIG="$T/.config/loaf/config.toml"

pass() { echo "ok   $1"; }
fail() { echo "FAIL $1" >&2; exit 1; }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }

HOME="$T" bash "$REPO/scripts/install.sh" --vault "~/MyVault" --schedule >/dev/null
check "runtime copy has the task format" '[[ -f "$SUPPORT/TASK-FORMAT.md" ]]'
check "runtime copy has run.sh and SKILL.md" '[[ -f "$SUPPORT/routines/morning-brief/run.sh" && -f "$SUPPORT/routines/morning-brief/SKILL.md" ]]'
check "contract points at the runtime copy" 'grep -qF "contract = \"$SUPPORT/TASK-FORMAT.md\"" "$CONFIG"'
check "vault written" 'grep -qF "vault = \"~/MyVault\"" "$CONFIG"'
check "skills copied" '[[ -f "$T/.claude/skills/loaf-notes/SKILL.md" && -f "$T/.claude/skills/loaf-brief/SKILL.md" ]]'
check "plist runs the runtime copy" 'grep -qF "$SUPPORT/routines/morning-brief/run.sh" "$T/Library/LaunchAgents/com.loaf.morning-brief.plist"'
check "no placeholder left in plist" '! grep -q REPLACE_WITH "$T/Library/LaunchAgents/com.loaf.morning-brief.plist"'

rm -rf "$T/.claude/skills"
HOME="$T" bash "$REPO/scripts/install.sh" --vault "/tmp/Other" --skip-skills >/dev/null
check "re-run leaves one vault and one contract line" '[[ "$(grep -cE "^(vault|contract) *=" "$CONFIG")" == 2 ]]'
check "re-run replaced the vault" 'grep -qF "vault = \"/tmp/Other\"" "$CONFIG"'
check "--skip-skills copies no skills" '[[ ! -d "$T/.claude/skills" ]]'

printf '[dates]\nsoon_within_days = 3\n' > "$CONFIG"
HOME="$T" bash "$REPO/scripts/install.sh" --vault "~/V3" --skip-skills >/dev/null
check "keys land above a [section], not inside it" '[[ "$(head -1 "$CONFIG")" == "vault = \"~/V3\"" ]] && grep -q "^\[dates\]" "$CONFIG"'

# run.sh prepends $HOME/.local/bin to PATH, so this stub stands in for claude.
mkdir -p "$T/vault" "$T/.local/bin"
printf '#!/bin/bash\nprintf "%%s\\n" "$@" > "$HOME/claude-args.txt"\n' > "$T/.local/bin/claude"
chmod +x "$T/.local/bin/claude"
HOME="$T" bash "$SUPPORT/routines/morning-brief/run.sh" --vault "$T/vault" --force >/dev/null
check "run.sh from the runtime copy injects the task format" 'grep -q "@due" "$T/claude-args.txt"'

ditto -c -k --keepParent "$REPO/dist/Loaf.app" "$T/Loaf.zip"
mkdir -p "$T/apps"
LOAF_APP_ZIP_URL="file://$T/Loaf.zip" LOAF_APP_DIR="$T/apps" bash "$REPO/scripts/install-app.sh" --no-open >/dev/null
check "app installed with a valid signature" 'codesign --verify --deep --strict "$T/apps/Loaf.app"'

mkdir -p "$T/empty" && echo x > "$T/empty/x.txt" && ditto -c -k "$T/empty" "$T/bad.zip"
check "a zip without Loaf.app is rejected" '! LOAF_APP_ZIP_URL="file://$T/bad.zip" LOAF_APP_DIR="$T/apps" bash "$REPO/scripts/install-app.sh" --no-open >/dev/null 2>&1'
check "the rejected zip left the installed app alone" '[[ -d "$T/apps/Loaf.app" ]]'

echo "PASS — installer checks"
