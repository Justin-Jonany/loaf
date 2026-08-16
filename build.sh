#!/usr/bin/env bash
# Builds Foolscap.app into ./dist. Requires a working Swift toolchain
# (see README → Troubleshooting if `swift build` reports an SDK mismatch).
set -euo pipefail

APP="dist/Foolscap.app"
CONTENTS="$APP/Contents"

swift build -c release --product foolscap

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$(swift build -c release --show-bin-path)/foolscap" "$CONTENTS/MacOS/Foolscap"
cp Resources/Info.plist "$CONTENTS/Info.plist"
cp -R Resources/themes "$CONTENTS/Resources/themes"
cp -R templates "$CONTENTS/Resources/templates"

echo "Built $APP"
echo "Install with:  cp -R $APP ~/Applications/"
