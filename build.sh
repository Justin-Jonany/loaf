#!/usr/bin/env bash
# Builds Loaf.app into ./dist. Requires a working Swift toolchain
# (see README → Troubleshooting if `swift build` reports an SDK mismatch).
set -euo pipefail

APP="dist/Loaf.app"
CONTENTS="$APP/Contents"

swift build -c release --product loaf

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$(swift build -c release --show-bin-path)/loaf" "$CONTENTS/MacOS/Loaf"
cp Resources/Info.plist "$CONTENTS/Info.plist"
cp -R Resources/themes "$CONTENTS/Resources/themes"
cp -R templates "$CONTENTS/Resources/templates"

echo "Built $APP"
echo "Install with:  cp -R $APP ~/Applications/"
