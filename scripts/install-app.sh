#!/usr/bin/env bash
set -euo pipefail

# Downloads the latest Loaf.app release and launches it. It replaces an existing copy in
# /Applications if there is one, since two installed copies make it easy to run a stale
# one; otherwise it installs to ~/Applications, which needs no admin rights. Used by the
# loaf-setup skill; from a clone you can instead build it yourself with ./build.sh.
#
#   scripts/install-app.sh [--no-open]
#
# LOAF_APP_ZIP_URL overrides where the zip comes from (tests, or a pinned version), and
# LOAF_APP_DIR the folder it installs into.
#
# curl doesn't set the quarantine attribute a browser download gets, so Gatekeeper
# doesn't block this unsigned build the way it would a zip opened from Downloads.

URL="${LOAF_APP_ZIP_URL:-https://github.com/Justin-Jonany/loaf/releases/latest/download/Loaf.zip}"
if [[ -n "${LOAF_APP_DIR:-}" ]]; then
  DEST="$LOAF_APP_DIR"
elif [[ -d /Applications/Loaf.app ]]; then
  DEST=/Applications
else
  DEST="$HOME/Applications"
fi
OPEN=1
[[ "${1:-}" == "--no-open" ]] && OPEN=""

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Downloading $URL"
curl -fsSL "$URL" -o "$WORK/Loaf.zip"
ditto -x -k "$WORK/Loaf.zip" "$WORK"
[[ -d "$WORK/Loaf.app" ]] || { echo "install-app.sh: the zip has no Loaf.app at its root" >&2; exit 1; }

# A running copy keeps its old binary, so stop the one being replaced (and only that
# one). Its writes are atomic and immediate, so there's no unsaved state to lose.
pkill -f "^$DEST/Loaf.app/Contents/MacOS/Loaf" 2>/dev/null || true

mkdir -p "$DEST"
rm -rf "$DEST/Loaf.app"
mv "$WORK/Loaf.app" "$DEST/Loaf.app"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$DEST/Loaf.app/Contents/Info.plist")"
echo "Installed Loaf $version to $DEST/Loaf.app"

[[ -n "$OPEN" ]] && open "$DEST/Loaf.app"
exit 0
