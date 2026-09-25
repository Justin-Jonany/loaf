#!/usr/bin/env bash
# Builds Loaf.app into ./dist. Requires a working Swift toolchain
# (see README → Troubleshooting if `swift build` reports an SDK mismatch).
set -euo pipefail

#
# LOAF_UNIVERSAL=1 builds for both Apple Silicon and Intel, as releases do. That needs
# a full Xcode install (Command Line Tools alone can't), so it's opt-in.

APP="dist/Loaf.app"
CONTENTS="$APP/Contents"

ARCH_FLAGS=()
[[ -n "${LOAF_UNIVERSAL:-}" ]] && ARCH_FLAGS=(--arch arm64 --arch x86_64)
# The `+` expansion keeps an empty array legal under `set -u` on macOS's bash 3.2.
swift build -c release --product loaf ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$(swift build -c release --show-bin-path ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"})/loaf" "$CONTENTS/MacOS/Loaf"
cp Resources/Info.plist "$CONTENTS/Info.plist"
# Pre-rendered by scripts/make-icons.sh, so the build itself needs no image tooling.
cp Resources/AppIcon.icns Resources/MenuBarIcon.png Resources/MenuBarIcon@2x.png "$CONTENTS/Resources/"
cp -R Resources/themes "$CONTENTS/Resources/themes"
cp -R templates "$CONTENTS/Resources/templates"

# Ad-hoc sign the assembled bundle: Apple Silicon refuses to launch unsigned code, and
# copying resources in after the linker's own signature leaves the bundle's seal broken.
codesign --force --sign - "$APP"

echo "Built $APP"
echo "Install with:  cp -R $APP ~/Applications/"
